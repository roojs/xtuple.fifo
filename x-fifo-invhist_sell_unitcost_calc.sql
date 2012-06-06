-- This routine should return total cost.

-- using invsell_totalcostbefore is totally unreliable..
-- 


CREATE OR REPLACE FUNCTION invhist_sell_unitcost_calc(integer)
  RETURNS numeric(16, 6) AS
$BODY$
DECLARE
  -- Variable naming :  i_ = INPUT,  v_ = Variables
  i_invhist_id         ALIAS FOR $1;
  v_itemsite_id integer;
  v_invsell_qtybefore numeric(18, 6) DEFAULT 0;
  v_invsell_totalcostbefore numeric(12, 2) DEFAULT 0;
  v_invsell_totalcostafter  numeric(12, 2) DEFAULT 0;
  v_invsell_qty numeric(18, 6) DEFAULT 0;
  
  v_totalcost_avail numeric(12, 2) DEFAULT 0;
  v_qty_avail numeric(18, 6) DEFAULT 0;

  v_calc_unitcost numeric(16, 6) DEFAULT 0;
  v_temp_a numeric(16, 6) DEFAULT 0;
  v_temp_b numeric(16, 6) DEFAULT 0;
  v_temp_c  numeric(16, 6) DEFAULT 0;
  
  
BEGIN 

    -- find record by invhist_id and get orders
    -- itemsite_id, qty and qtybefore
    
-- add our cost before value here..    
    SELECT  invsell_itemsite_id,
            COALESCE(invsell_qtybefore,0),
            invsell_qty
         FROM
            invsell 
        INTO
            v_itemsite_id,
            v_invsell_qtybefore,
            v_invsell_qty
        WHERE 
            invsell_invhist_id = i_invhist_id;


    --RAISE NOTICE 'i_invhist_id=%', i_invhist_id;
    --RAISE NOTICE 'v_itemsite_id=%', v_itemsite_id;
    --RAISE NOTICE 'v_invsell_qty=%', v_invsell_qty;
    --RAISE NOTICE 'v_invsell_qtybefore=%', v_invsell_qtybefore;
    
    -- FIND ALL THE STOCK WE CAN USE UP..
    
    -- The price of what we need is
    -- total after - total before - what's left over..
    
    
    
    
    
    
    
--BUY: (after | qty)
--   18   18  ($4.65)
--   24   6   ($2.63)
--   28   4
--   32   4
   
--SELL: (before | qty)
--   0    3
--   3    2
--   5    4
--   9   1
--   10  3
--   13  6
--  19   4
    
-- GET THE $ value of stock available before we change.

    SELECT
        
        invbuy_totalcostafter 
            - ((invbuy_qtyafter - v_invsell_qtybefore) * invbuy_unitcost)
        INTO
            v_invsell_totalcostbefore
        FROM
            invbuy
        WHERE
            invbuy_qtyafter >= v_invsell_qtybefore
            AND
            invbuy_itemsite_id = v_itemsite_id
        ORDER BY
            invbuy_qtyafter ASC
            
        LIMIT 1;
         
    
    --RAISE NOTICE 'v_invsell_totalcostbefore=%', v_invsell_totalcostbefore;
    
    
    -- NEXT JUST DO THE SAME AND find the quantity AFTER..
      SELECT
        invbuy_totalcostafter 
             - ((invbuy_qtyafter - (v_invsell_qtybefore + v_invsell_qty)) * invbuy_unitcost)
        INTO
            v_invsell_totalcostafter
        FROM
            invbuy
        WHERE
            invbuy_qtyafter >= v_invsell_qtybefore + v_invsell_qty
            AND
            invbuy_itemsite_id = v_itemsite_id
        ORDER BY
            invbuy_qtyafter ASC
        LIMIT 1;
         
    
    --RAISE NOTICE 'v_invsell_totalcostafter=%', v_invsell_totalcostafter;
    
    
    
    v_totalcost_avail := COALESCE(v_invsell_totalcostafter- v_invsell_totalcostbefore,0);
    
    SELECT
        max(invbuy_qtyafter)
            - (v_invsell_qtybefore + v_invsell_qty)
    INTO
        v_qty_avail
        
        FROM
            invbuy
        WHERE
            invbuy_itemsite_id = v_itemsite_id
        
        LIMIT 1;
    
    v_qty_avail := COALESCE(v_qty_avail,0);
    
    IF (v_qty_avail > v_invsell_qty) THEN
        v_qty_avail  := v_invsell_qty;
    END IF;
    
    IF (v_qty_avail <= 0) THEN
        v_qty_avail  := 0;
    END IF;
    
    
    --RAISE NOTICE 'v_totalcost_avail=%', v_totalcost_avail;
    --RAISE NOTICE 'v_qty_avail=%', v_qty_avail;
   

    
    
    -- if not found inventory for sell
    if (v_qty_avail <= 0) THEN
        -- if really not found any inventory for sell
        -- then use last unitcost for this itemsite
         
              -- find the last unitcost..
        SELECT
                invbuy_unitcost
            INTO
                v_calc_unitcost
            FROM
                invbuy
            WHERE
                invbuy_itemsite_id = v_itemsite_id    
            ORDER BY
                invbuy_qtyafter DESC
            LIMIT
                1;
 
    
        -- if not found any inventory of this itemsite
        -- then use standard cost for this itemsite
        IF (NOT FOUND) THEN
            v_calc_unitcost = stdcost(v_itemsite_id);
        END IF;    
        
        RETURN ABS(v_calc_unitcost);
    END IF;

    
    RETURN ABS(floor(( v_totalcost_avail/ v_qty_avail) * 1000) / 1000);
    
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

ALTER FUNCTION  invhist_sell_unitcost_calc(integer)
  OWNER TO admin;

 
CREATE OR REPLACE FUNCTION invhist_sell_unitcost_update(integer)
  RETURNS  INT AS
$BODY$
DECLARE
  -- Variable naming :  i_ = INPUT,  v_ = Variables
  i_invhist_id         ALIAS FOR $1;
  BEGIN 

    -- find record by invhist_id and get orders
    -- itemsite_id, qty and qtybefore
    
-- add our cost before value here..    
    
    UPDATE invsell
        SET
            invsell_calc_unitcost = invhist_sell_unitcost_calc(invsell_invhist_id)   
        WHERE 
            invsell_invhist_id = i_invhist_id;
    
    UPDATE invsell
        SET
            invsell_calc_totalcost = invsell_qty * invsell_calc_unitcost 
        WHERE 
            invsell_invhist_id = i_invhist_id;
            
    RETURN 1;       
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

ALTER FUNCTION  invhist_sell_unitcost_update(integer)
  OWNER TO admin;
  
  
  
  