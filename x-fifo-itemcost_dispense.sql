CREATE OR REPLACE FUNCTION itemcost_dispense (integer, numeric(18, 6))  RETURNS  numeric(16, 6)
AS $BODY$
DECLARE
  -- Variable naming :  i_ = INPUT,  v_ = Variables
  i_itemsite_id         ALIAS FOR $1;
  i_invsell_qty         ALIAS FOR $2;
  v_invsell_qtybefore numeric(18, 6) DEFAULT 0;
  v_invsell_totalcostbefore numeric(12, 2) DEFAULT 0;
  v_invsell_calc_totalcost numeric(12, 2) DEFAULT 0;
  
  v_invsell_qty numeric(18, 6) DEFAULT 0;
  v_itemsite_costmethod character(1);
  
  v_totalcost_avail numeric(12, 2) DEFAULT 0;
  v_qty_avail numeric(18, 6) DEFAULT 0;

  v_calc_unitcost numeric(16, 6) DEFAULT 0;
  
BEGIN 

    -- find record by invhist_id and get orders
    -- itemsite_id, qty and qtybefore

    i_invsell_qty := abs(i_invsell_qty);

    SELECT itemsite_costmethod INTO v_itemsite_costmethod
        FROM itemsite 
        WHERE itemsite_id = i_itemsite_id;
    
    -- if FIFO method not used 
    IF ( v_itemsite_costmethod <> 'F' AND NOT fetchMetricBool('UseStandardAsFIFO') ) THEN
        RAISE NOTICE 'NOT FIFO?';
        RETURN stdcost(i_itemsite_id);
    END IF;
    
    
    
-- add our cost before value here..
-- what if not found..
    SELECT 
            invsell_qtybefore, invsell_totalcostbefore, 
            invsell_qty, invsell_calc_totalcost
            
        FROM invsell 
        INTO 
                v_invsell_qtybefore, v_invsell_totalcostbefore, 
                v_invsell_qty, v_invsell_calc_totalcost
        WHERE 
            invsell_itemsite_id = i_itemsite_id
            AND
            invsell_is_estimate = false
        ORDER BY invsell_qtybefore DESC
        LIMIT 1;

   
    IF NOT FOUND THEN
        v_invsell_qtybefore = 0;
        v_invsell_totalcostbefore = 0;
    
    ELSE 
    
        v_invsell_qtybefore = v_invsell_qtybefore + v_invsell_qty;
        v_invsell_totalcostbefore = v_invsell_totalcostbefore + v_invsell_calc_totalcost;
    END IF;
    
    
    RAISE NOTICE 'look up stock cost.';
    
    
    SELECT 
        -- we take all the stock
        SUM(invbuy_totalcost)
        
        -- we take leftovers
        - (v_invsell_totalcostbefore - min(invbuy_totalcostafter-invbuy_totalcost)) 

        -- we take upto how many we need
        - (max(invbuy_qtyafter)-v_invsell_qtybefore-i_invsell_qty)
            *(max(invbuy_totalcostafter) - max(invbuy_totalcostafter-invbuy_totalcost))/(max(invbuy_qtyafter) - max(invbuy_qtyafter-invbuy_qty)) totalcost,

        SUM(invbuy_qty)
        
        - (v_invsell_qtybefore - min(invbuy_qtyafter - invbuy_qty))
        
        - (max(invbuy_qtyafter)-v_invsell_qtybefore-i_invsell_qty) qty
        
        FROM invbuy 
        INTO v_totalcost_avail, v_qty_avail
            WHERE
                invbuy_itemsite_id = i_itemsite_id
                AND
                invbuy_qtyafter > v_invsell_qtybefore
                AND
                invbuy_qtyafter - invbuy_qty < v_invsell_qtybefore + i_invsell_qty;

    
    
    
    -- if not found inventory for sell
    if (v_qty_avail < 0 OR v_qty_avail IS NULL) THEN
    
    
        RAISE NOTICE 'QTY < 0 or not found..';
        RAISE NOTICE 'v_calc_unitcost=%', v_calc_unitcost;
        -- if really not found any inventory for sell
        
        -- then use last unitcost for this itemsite
        IF (v_qty_avail < 0) THEN
            RAISE NOTICE 'NOT FOUND.. trying to find last trax..';
        
            SELECT 
                (invhist_value_after - invhist_value_before)
                    / (invhist_qoh_after - invhist_qoh_before) AS unitcost
                FROM invhist INTO v_calc_unitcost
                    WHERE 
                        invhist_itemsite_id = i_itemsite_id
                        AND
                        invhist_qoh_after - invhist_qoh_before <> 0
                ORDER BY invhist_transdate DESC, invhist_id DESC
                LIMIT 1;
             
             
            
        END IF;
        RAISE NOTICE 'v_calc_unitcost=%', v_calc_unitcost;
        -- if not found any inventory of this itemsite
        -- then use standard cost for this itemsite
        
        IF (v_calc_unitcost IS NULL or v_calc_unitcost = 0.0) THEN
            v_calc_unitcost = stdcost(i_itemsite_id);
        END IF;
        
        RAISE NOTICE 'v_calc_unitcost=%', v_calc_unitcost;
        
        RETURN v_calc_unitcost;

    END IF;
        
    RAISE NOTICE 'v_totalcost_avail = %', v_totalcost_avail;
    RAISE NOTICE 'v_qty_avail= %', v_qty_avail;
    
    RETURN floor(( v_totalcost_avail/ v_qty_avail) * 1000) / 1000;
    
END
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
  
ALTER FUNCTION  itemcost_dispense(integer, numeric(18, 6))
  OWNER TO admin;
