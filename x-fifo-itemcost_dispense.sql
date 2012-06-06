CREATE OR REPLACE FUNCTION itemcost_dispense (integer, numeric(18, 6))  RETURNS  numeric(16, 6)
AS $BODY$
DECLARE
  -- Variable naming :  i_ = INPUT,  v_ = Variables
  i_itemsite_id         ALIAS FOR $1;
  i_invsell_qty         ALIAS FOR $2;
  v_invsell_qtybefore numeric(18, 6) DEFAULT 0;
   v_invsell_calc_totalcost numeric(12, 2) DEFAULT 0;
  
  v_invsell_qty numeric(18, 6) DEFAULT 0;
  v_itemsite_costmethod character(1);
  
  v_totalcost_avail numeric(12, 2) DEFAULT 0;
  v_qty_avail_before numeric(18, 6) DEFAULT 0;
  v_qty_avail numeric(18, 6) DEFAULT 0;
  v_qty_sold numeric(18, 6) DEFAULT 0;
  
  v_invsell_totalcostbefore numeric(18, 6) DEFAULT 0;
  v_invsell_totalcostafter numeric(18, 6) DEFAULT 0;
  

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
    
    
    -- how many do we have.
    SELECT
            COALESCE(max(invbuy_qtyafter), 0)
        INTO
           v_qty_avail_before
        FROM
            invbuy
        WHERE
            invbuy_itemsite_id = i_itemsite_id;
             
    
    
    -- how many have been sold, 
    
    SELECT
            COALESCE(max(invsell_qtybefore + invsell_qty),0)
        INTO
            v_qty_sold
        FROM
            invsell
        WHERE
            invsell_itemsite_id = i_itemsite_id;
             
    v_qty_avail := v_qty_avail_before - v_qty_sold;
   
    -- not enough.. 
    if (v_qty_avail < i_invsell_qty ) THEN
    
        -- find the last unitcost..
        SELECT
                invbuy_unitcost
            INTO
                v_calc_unitcost
            FROM
                invbuy
            WHERE
                invbuy_itemsite_id = i_itemsite_id    
            ORDER BY
                invbuy_qtyafter DESC
            LIMIT
                1;
        
        
        RAISE NOTICE 'QTY < 0 or not found..';
        RAISE NOTICE 'v_calc_unitcost=%', v_calc_unitcost;
        -- if really not found any inventory for sell
        
        -- then use last unitcost for this itemsite
        
        -- if not found any inventory of this itemsite
        -- then use standard cost for this itemsite
        
        IF (NOT FOUND) THEN
            v_calc_unitcost = stdcost(i_itemsite_id);
            -- what if that return nothing...
        END IF;
        
        RAISE NOTICE 'v_calc_unitcost=%', v_calc_unitcost;
        
        RETURN v_calc_unitcost;

    END IF;
    
    
    -- FINALLY DO OUR PRICING...
    -- same as calc code..
    
    SELECT
        
        invbuy_totalcostafter 
            - ((invbuy_qtyafter - v_qty_sold) * invbuy_unitcost)
        INTO
            v_invsell_totalcostbefore
        FROM
            invbuy
        WHERE
            invbuy_qtyafter >= v_qty_sold
            AND
            invbuy_itemsite_id = i_itemsite_id
        ORDER BY
            invbuy_qtyafter ASC
            
        LIMIT 1;
         
    
    RAISE NOTICE 'v_invsell_totalcostbefore=%', v_invsell_totalcostbefore;
    
    RAISE NOTICE 'v_qty_sold=%', v_qty_sold;
    RAISE NOTICE 'i_invsell_qty=%', i_invsell_qty;
    
    -- NEXT JUST DO THE SAME AND find the quantity AFTER..
    SELECT
        invbuy_totalcostafter 
             - ((invbuy_qtyafter - (v_qty_sold + i_invsell_qty)) * invbuy_unitcost)
        INTO
            v_invsell_totalcostafter
        FROM
            invbuy
        WHERE
            invbuy_qtyafter >= v_qty_sold + i_invsell_qty
            AND
            invbuy_itemsite_id = i_itemsite_id
        ORDER BY
            invbuy_qtyafter ASC
        LIMIT 1;
         
    
    RAISE NOTICE 'v_invsell_totalcostafter=%', v_invsell_totalcostafter;
    
    
    
    v_totalcost_avail := COALESCE(v_invsell_totalcostafter- v_invsell_totalcostbefore,0);
    
     
    RETURN ABS(floor(( v_totalcost_avail/ i_invsell_qty) * 1000) / 1000);
    
    
END
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
  
ALTER FUNCTION  itemcost_dispense(integer, numeric(18, 6))
  OWNER TO admin;
