--- THIS DOES NOT WORK YET - hence we remove the trigger..
--DROP TRIGGER _invhisttriggerfifo ON invhist;


CREATE OR REPLACE FUNCTION invhisttriggerfifo() RETURNS trigger 
AS $BODY$
DECLARE
    v_trans_qty             numeric(18, 6);
    v_new_invhist_id        integer;
    v_qtyafter              numeric(18, 6);
    v_qtyafter_old          numeric(18, 6);
    v_qtybefore             numeric(18, 6);
    v_qtybefore_old         numeric(18, 6);
    v_qtydiff               numeric(18, 6);
    v_totalcostdiff         numeric(12, 2);
    v_totalcostafter        numeric(12, 2);
    v_totalcostafter_old    numeric(12, 2);
    
    v_totalcostbefore_diff  numeric(18, 6);

    v_qty_before_min        numeric(18, 6);
    
    v_new_invbuy_data       record;
    
    v_is_new                boolean;
    
    v_first_transdate       timestamp with time zone;
    v_first_invhist_id      integer;
    v_new_totalcost         numeric(12, 2);
    v_itemsite_id           integer;
    
    v_max_invbuy_qtyafter   numeric(12, 2);
        
       
    new_inv_buy             record;
    
    new_inv_sell            record;
    
BEGIN
    
    v_trans_qty := NEW.invhist_qoh_after - NEW.invhist_qoh_before;
    
    --determine type of transaction, BUY or SELL
     
    IF NOT NEW.invhist_posted THEN
        RETURN NEW;
    END IF;
    
    -- excluding variants where invhist record is already posted, but it transaction don't update value of qty, totalcost, or unitcost.
    IF TG_OP = 'UPDATE' THEN
        IF (
            OLD.invhist_posted
            AND
            v_trans_qty = OLD.invhist_qoh_after - OLD.invhist_qoh_before 
            AND
            NEW.invhist_value_after - NEW.invhist_value_before = 
                OLD.invhist_value_after - OLD.invhist_value_before 
            AND
            NEW.invhist_unitcost = OLD.invhist_unitcost
         )    
        THEN
            RETURN NEW;
        END IF;
    END IF;

    
    -- invhist_transtype | RL << TRANSFER.. -- ignored..
    -- invhist_transtype | RS (SELL)
    -- invhist_transtype | AD (BUY OR SELL)
    -- invhist_transtype | RP (BUY)
    -- invhist_transtype | SH (SELL)
            
    
    -- if BUY
    IF NEW.invhist_transtype = 'RP' 
        OR
        (NEW.invhist_transtype = 'AD' AND v_trans_qty > 0) THEN
    
        
        
            SELECT a2.ordernumber AS ordernumber, a2.itemsite_id AS itemsite_id, 
                   a2.qty AS qty, a2.totalcost AS totalcost, a2.unitcost AS unitcost,
                   i.invhist_id AS invhist_id, i.invhist_transdate AS transdate
                INTO new_inv_buy
                
                FROM
                    (
                        SELECT
                            min(invhist_id) AS invhist_id,
                            invhist_ordnumber  AS ordernumber,
                            invhist_itemsite_id                             AS itemsite_id,
                            SUM(invhist_qoh_after - invhist_qoh_before)          AS qty,
                            SUM(invhist_value_after - invhist_value_before)    AS totalcost,
                            SUM(invhist_value_after - invhist_value_before)
                                / SUM(invhist_qoh_after - invhist_qoh_before)   AS unitcost
                        FROM
                            invhist
                        WHERE
                            invhist_itemsite_id = NEW.invhist_itemsite_id
                            AND
                            invhist_ordnumber = NEW.invhist_ordnumber
                            AND
                            invhist_transtype in ('RP', 'AD')
                            AND
                            invhist_posted = true
                        GROUP BY invhist_itemsite_id, invhist_ordnumber
                    ) AS a2, 
                    invhist AS i
                WHERE
                    a2.invhist_id = i.invhist_id
                LIMIT
                    1;
        
         
            
            IF NOT FOUND THEN
                v_is_new := true;
                v_first_transdate := NEW.invhist_transdate;
                v_first_invhist_id := NEW.invhist_id;
                new_inv_buy.qty := v_trans_qty;
                v_new_totalcost := NEW.invhist_value_after - NEW.invhist_value_before;
                v_itemsite_id := NEW.invhist_itemsite_id;
            ELSE
                v_is_new := false;
                v_first_transdate := new_inv_buy.transdate;
                v_first_invhist_id := new_inv_buy.invhist_id;
                v_new_totalcost := new_inv_buy.totalcost;
                v_itemsite_id := new_inv_buy.itemsite_id;
            END IF;

 
            SELECT invdepend_parent_id FROM invdepend
                WHERE
                        invdepend_parent_id = v_first_invhist_id
                    AND
                        invdepend_invhist_id = NEW.invhist_id;
                 

            IF NOT FOUND THEN
                INSERT INTO invdepend 
                    (invdepend_parent_id, invdepend_invhist_id)
                VALUES 
                    (v_first_invhist_id, NEW.invhist_id);
            END IF;
            
            SELECT invbuy_qtyafter, invbuy_totalcostafter 
            INTO v_qtyafter, v_totalcostafter 
            FROM invbuy 
                WHERE
                    invbuy_itemsite_id = v_itemsite_id
                    AND
                    ( 
                        invbuy_transdate <  v_first_transdate 
                        OR
                        (
                            invbuy_transdate =  v_first_transdate 
                            AND 
                            invbuy_invhist_id < v_first_invhist_id
                        )
                    )
            ORDER BY invbuy_qtyafter DESC
            LIMIT 1;
            
            v_qtyafter := COALESCE(v_qtyafter, 0) + new_inv_buy.qty;
            v_totalcostafter := COALESCE(v_totalcostafter, 0) + v_new_totalcost;
  
            IF v_is_new THEN
                -- create a new record..
                INSERT INTO invbuy 
                    (
                        invbuy_invhist_id, invbuy_transdate, 
                        invbuy_ordnumber, invbuy_itemsite_id, 
                        
                        invbuy_qty, invbuy_totalcost, 
                        invbuy_unitcost, invbuy_transtype, 
                        
                        invbuy_qtyafter, invbuy_totalcostafter,
                        invbuy_is_estimate
                    ) VALUES (
                        NEW.invhist_id, NEW.invhist_transdate, 
                        NEW.invhist_ordnumber, NEW.invhist_itemsite_id, 
                        
                        v_trans_qty, v_new_totalcost, 
                        NEW.invhist_unitcost, 'RP', 
                        
                        v_qtyafter, v_totalcostafter,
                        true
                    );
                    
                v_qtydiff := new_inv_buy.qty;
                v_totalcostdiff := new_inv_buy.totalcost;
            ELSE
                -- get the existing qty recorded..
                SELECT invbuy_qtyafter, invbuy_totalcostafter 
                INTO v_qtyafter_old, v_totalcostafter_old 
                FROM invbuy 
                    WHERE 
                        invbuy_invhist_id = new_inv_buy.invhist_id;
            
                UPDATE invbuy SET
                    invbuy_transdate = new_inv_buy.transdate,
                    invbuy_qty = new_inv_buy.qty,
                    invbuy_totalcost = new_inv_buy.totalcost,
                    invbuy_unitcost = new_inv_buy.unitcost,
                    invbuy_qtyafter = v_qtyafter,
                    invbuy_totalcostafter = v_totalcostafter
                WHERE 
                    invbuy_invhist_id = new_inv_buy.invhist_id;
                    
                v_qtydiff := v_qtyafter - v_qtyafter_old;
                v_totalcostdiff := v_totalcostafter - v_totalcostafter_old;
            END IF;
            
            UPDATE invbuy SET
                invbuy_qtyafter = invbuy_qtyafter + v_qtydiff,
                invbuy_totalcostafter = invbuy_totalcostafter + v_totalcostdiff
            WHERE 
               invbuy_itemsite_id = v_itemsite_id
               AND
               (
                   invbuy_transdate > v_first_transdate
                   OR 
                   (
                        invbuy_transdate = v_first_transdate 
                        AND 
                        invbuy_invhist_id > v_first_invhist_id
                    )
                );
            
            --find record in invsell, which uses it inventories
            SELECT max(invsell_qtybefore) 
                INTO 
                    v_qty_before_min
                FROM 
                    invsell 
                WHERE 
                    invsell_qtybefore < v_qtyafter 
                    AND 
                    invsell_itemsite_id = v_itemsite_id;
            
            -- recalc FIFO values for all records after current
            UPDATE invsell SET
                    invsell_calc_unitcost = invhist_sell_unitcost_calc(invsell_invhist_id),
                    invsell_calc_totalcost = invsell_qty * invsell_calc_unitcost
                    
                WHERE 
                    invsell_qtybefore >= v_qty_before_min 
                    AND 
                    invsell_itemsite_id = v_itemsite_id;
            
            SELECT max(invbuy_qtyafter)    
                INTO v_max_invbuy_qtyafter
                FROM invbuy;
            
            -- update estimated
            UPDATE invsell SET
                    invsell_is_estimate = true
                WHERE invsell_qtybefore + invsell_qty > v_max_invbuy_qtyafter;

            UPDATE invsell SET
                    invsell_totalcostbefore = b_invsell_summtotalcost
                FROM 
                    (
                        SELECT 
                            a.invsell_invhist_id a_invsell_invhist_id,
                            SUM(b.invsell_calc_totalcost) b_invsell_summtotalcost 
                            FROM invsell b, invsell a
                            WHERE
                                b.invsell_qtybefore    < a.invsell_qtybefore
                                AND
                                b.invsell_itemsite_id = a.invsell_itemsite_id
                                AND
                                a.invsell_itemsite_id = v_itemsite_id
                                AND 
                                a.invsell_qtybefore >= v_qty_before_min
                        GROUP BY a.invsell_invhist_id
                    ) dest
                WHERE 
                    invsell_invhist_id = a_invsell_invhist_id;
                    
            
    -- if SELL
    
    
    
     
    
    ELSIF
        NEW.invhist_transtype = 'SH'
        OR
        (NEW.invhist_transtype = 'AD' AND v_trans_qty < 0)
        OR
        NEW.invhist_transtype = 'RS' THEN
        
    
            
            SELECT  a2.ordernumber AS ordernumber,
                    a2.itemsite_id AS itemsite_id, 
                    a2.qty AS qty,
                    a2.current_totalcost AS current_totalcost,
                    a2.current_unitcost AS current_unitcost,
                    i.invhist_id AS invhist_id,
                    i.invhist_transdate AS transdate
                INTO
                    new_inv_sell
                FROM
                    (
                        SELECT
                            invhist_ordnumber                               AS ordernumber,
                            invhist_itemsite_id                             AS itemsite_id,
                            min(invhist_id)                                 AS invhist_id,
                            SUM(invhist_qoh_after - invhist_qoh_before)     AS qty,
                            SUM(invhist_value_after - invhist_value_before) AS current_totalcost,
        
                            SUM(invhist_value_after - invhist_value_before)
                                    / SUM(invhist_qoh_after - invhist_qoh_before)
                                                                              AS current_unitcost
                            
                        FROM
                            invhist
                        WHERE
                            invhist_itemsite_id = NEW.invhist_itemsite_id 
                            AND
                            invhist_ordnumber = NEW.invhist_ordnumber
                            AND
                            (invhist_transtype = 'SH' OR invhist_transtype = 'RS')
                            AND 
                            invhist_posted = true
                        GROUP BY
                            invhist_itemsite_id, invhist_ordnumber
                        HAVING
                            SUM(invhist_qoh_after - invhist_qoh_before) <> 0
                    ) AS a2,
                    invhist AS i
                WHERE
                    a2.invhist_id = i.invhist_id
                LIMIT
                    1;
         

            IF (NOT FOUND) THEN
                v_is_new = true;
                v_itemsite_id       = NEW.invhist_itemsite_id;
                v_first_transdate   = NEW.invhist_transdate;
                v_first_invhist_id  = NEW.invhist_id;
            ELSE
                v_is_new = false;
                v_itemsite_id       = new_inv_sell.itemsite_id;
                v_first_transdate   = new_inv_sell.transdate;
                v_first_invhist_id  = new_inv_sell.invhist_id;
            END IF;
            -- find the previous qty.. before this transaction..
            
            
            SELECT invdepend_parent_id FROM invdepend
                WHERE
                        invdepend_parent_id = v_first_invhist_id
                    AND
                        invdepend_invhist_id = NEW.invhist_id;
                 

            IF NOT FOUND THEN
                INSERT INTO invdepend 
                    (invdepend_parent_id, invdepend_invhist_id)
                VALUES 
                    (v_first_invhist_id, NEW.invhist_id);
            END IF;
          
            
            SELECT invsell_qtybefore 
                INTO v_qtybefore
                FROM invsell 
                    WHERE
                        invsell_itemsite_id = v_itemsite_id
                        AND   
                        ( 
                            invsell_transdate <  v_first_transdate 
                            OR
                            (
                                invsell_transdate =  v_first_transdate 
                                AND 
                                invsell_invhist_id < v_first_invhist_id
                            )
                        )
                ORDER BY invsell_qtybefore DESC
                LIMIT 1;
            
            v_qtybefore := COALESCE(v_qtybefore, 0);
            
            IF (v_is_new) THEN
                -- create a new record..
                INSERT INTO invsell 
                    (
                        invsell_invhist_id, invsell_transdate, 
                        invsell_itemsite_id, invsell_ordnumber, 
                        
                        invsell_qty, invsell_current_totalcost, 
                        invsell_current_unitcost, invsell_transtype, 
                        
                        invsell_qtybefore, invsell_is_estimate
                    ) VALUES (
                        NEW.invhist_id, NEW.invhist_transdate, 
                        NEW.invhist_itemsite_id, NEW.invhist_ordnumber, 
                        
                        v_trans_qty, NEW.invhist_value_after - NEW.invhist_value_before, 
                        NEW.invhist_unitcost, 'SH', 
                        
                        v_qtybefore, true
                    );
                v_qtydiff := new_inv_sell.qty;
                
            ELSE
                -- get the existing qty recorded..
                SELECT invsell_qtybefore 
                INTO v_qtybefore_old 
                FROM invsell 
                    WHERE invsell_invhist_id = new_inv_sell.invhist_id;
            
                UPDATE invsell SET
                    invsell_transdate   = new_inv_sell.transdate,
                    invsell_qty         = new_inv_sell.qty,
                    invsell_current_totalcost = new_inv_sell.current_totalcost,
                    invsell_current_unitcost = new_inv_sell.current_unitcost,
                    invsell_qtybefore   = invsell_qtybefore + v_qtybefore
                WHERE invsell_invhist_id = new_inv_sell.invhist_id;
                
                v_qtydiff := v_qtybefore - v_qtybefore_old;
            END IF;
            
            -- update qty's after the record..
            UPDATE invsell SET
                    invsell_qtybefore = invsell_qtybefore + v_qtydiff
                WHERE 
                    invsell_itemsite_id = v_itemsite_id
                    AND
                    (
                        invsell_transdate > v_first_transdate
                        OR 
                        (
                            invsell_transdate = v_first_transdate 
                            AND 
                            invsell_invhist_id > v_first_invhist_id
                        )
                    );
            
            -- recalc FIFO values for all records after current
            UPDATE invsell SET
                    invsell_calc_unitcost = invhist_sell_unitcost_calc(invsell_invhist_id),
                    invsell_calc_totalcost = invsell_qty * invsell_calc_unitcost
                    
                WHERE 
                    invsell_qtybefore >= v_qtybefore 
                    AND 
                    invsell_itemsite_id = v_itemsite_id;
            
            SELECT max(invbuy_qtyafter)    
                 INTO v_max_invbuy_qtyafter
                 FROM invbuy;
            
            -- update estimated
            UPDATE invsell SET
                    invsell_is_estimate = true
                WHERE invsell_qtybefore + invsell_qty > v_max_invbuy_qtyafter;

            UPDATE invsell SET
                    invsell_totalcostbefore = b_invsell_summtotalcost
                FROM 
                    (
                        SELECT 
                            a.invsell_invhist_id a_invsell_invhist_id,
                            SUM(b.invsell_calc_totalcost) b_invsell_summtotalcost 
                            FROM invsell b, invsell a
                            WHERE
                                b.invsell_qtybefore    < a.invsell_qtybefore
                                AND
                                b.invsell_itemsite_id = a.invsell_itemsite_id
                                AND
                                a.invsell_itemsite_id = v_itemsite_id
                                AND
                                a.invsell_qtybefore >= v_qtybefore
                        GROUP BY a.invsell_invhist_id
                    ) dest
                WHERE 
                    invsell_invhist_id = a_invsell_invhist_id;
            
            
            
    END IF;
        
    RETURN NEW;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
  
ALTER FUNCTION  invhisttriggerfifo(integer)
  OWNER TO admin;

