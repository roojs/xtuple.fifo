-- THIS IS A VIEW BASED VERSION OF THE FIFO CALC.

-- it needs to be turned into a materialized view using triggers on invhist



-- View: invhist_buy

 
CREATE OR REPLACE FUNCTION invhist_firstid(int, text, text)
  RETURNS  int  AS
$BODY$
DECLARE
  
  i_itemsite ALIAS FOR $1;
  i_order ALIAS FOR $2;
  i_type  ALIAS FOR $3;
  v_ret INT;
   
BEGIN
    
    SELECT invhist_id INTO v_ret
            FROM
                invhist
            WHERE
                invhist_itemsite_id = i_itemsite
                AND
                invhist_ordnumber = i_order
                AND
                invhist_transtype = i_type 
            ORDER BY
                invhist_id ASC
            LIMIT 1 ;
        
    RETURN v_ret; 
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
  
  
ALTER FUNCTION  invhist_firstid(int, text, text)
  OWNER TO admin;
  
  
  
  
CREATE OR REPLACE FUNCTION invhist_firstdate(int, text, text)
  RETURNS timestamp with time zone  AS
$BODY$
DECLARE
  
  i_itemsite ALIAS FOR $1;
  i_order ALIAS FOR $2;
  i_type  ALIAS FOR $3;
  v_ret  timestamp with time zone ;
   
BEGIN
    
    SELECT invhist_transdate INTO v_ret
            FROM
                invhist
            WHERE
                invhist_itemsite_id = i_itemsite
                AND
                invhist_ordnumber = i_order
                AND
                invhist_transtype = i_type 
            ORDER BY
                invhist_id ASC
            LIMIT 1 ;
        
    RETURN v_ret; 
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION  invhist_firstdate(int, text, text)
  OWNER TO admin;
 

DROP VIEW invhist_buy ;
-- buy is a mix of RP and +ve adjustments.
CREATE OR REPLACE VIEW invhist_buy AS


     SELECT
        distinct(invhist_ordnumber)  AS ordernumber,
        invhist_itemsite_id                             AS itemsite_id,
        SUM(invhist_qoh_after - invhist_qoh_before)          AS qty,
        SUM(invhist_value_after - invhist_value_before)    AS totalcost,
        SUM(invhist_value_after - invhist_value_before)
            / SUM(invhist_qoh_after - invhist_qoh_before)   AS unitcost,
        'RP'                                        AS transtype ,
        
        invhist_firstid(invhist_itemsite_id, invhist_ordnumber, 'RP')
                                                        AS invhist_id,
                                                        
        invhist_firstdate(invhist_itemsite_id, invhist_ordnumber, 'RP')
                                                         AS transdate ,
        0 AS qtyafter
        
    FROM
        invhist
    WHERE
        invhist_transtype = 'RP'
        AND
        invhist_posted = true
    GROUP BY
        invhist_ordnumber,
        invhist_itemsite_id
         
        ;
            

ALTER TABLE invhist_buy
  OWNER TO admin;
GRANT ALL ON TABLE invhist_buy TO admin;
GRANT ALL ON TABLE invhist_buy TO xtrole;





CREATE OR REPLACE FUNCTION invhist_buy_after(int)
  RETURNS  numeric(18,6)  AS
$BODY$
DECLARE
  i_id ALIAS FOR $1;
  v_itemsite_id INTEGER;
  v_transdate timestamp with time zone;
  v_qty numeric(18,6) ;
  v_return numeric(18,6) ;
BEGIN
    v_return := 0;




   SELECT
      itemsite_id,
     transdate,
     qty
        INTO
        v_itemsite_id, 
        v_transdate,
        v_qty
        FROM invhist_buy 
        WHERE
            invhist_id = i_id
        LIMIT 1;
   

-- # when transactions are the same day, we only want to include the ones with lower ids..


    SELECT   COALESCE(SUM( qty), 0) + v_qty INTO v_return 
        FROM invhist_buy 
        WHERE
            itemsite_id = v_itemsite_id
            AND   ( 
                transdate <  v_transdate 
                OR
                (transdate =  v_transdate AND invhist_id < i_id)
            )  ;

    IF (v_return IS NULL) THEN 
        v_return = 0;
    END IF;


 

  RETURN v_return;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION  invhist_buy_after(int)
  OWNER TO admin;


 

-- #------------- SELL


DROP VIEW invhist_sell ;
 
-- buy is a mix of RP and +ve adjustments.
CREATE OR REPLACE VIEW invhist_sell AS

-- should this use ordnum + docnumber..

     SELECT
        distinct(invhist_ordnumber)  AS ordernumber,
        invhist_itemsite_id                             AS itemsite_id,
        SUM(invhist_qoh_after - invhist_qoh_before)          AS qty,
        SUM(invhist_value_after - invhist_value_before)    AS current_totalcost,
        
        
        CASE
            WHEN SUM(invhist_qoh_after - invhist_qoh_before) = 0.0
            THEN 0.0
            ELSE  
            SUM(invhist_value_after - invhist_value_before)
                / SUM(invhist_qoh_after - invhist_qoh_before)
            END
                                                          AS current_unitcost,
        
        'SH'                                   AS ordertype ,
        
        invhist_firstid(invhist_itemsite_id, invhist_ordnumber, 'SH')
                                                        AS invhist_id,
                                                        
        invhist_firstdate(invhist_itemsite_id, invhist_ordnumber, 'SH')
                                                         AS transdate,
        
        0 AS qtyafter,
        0.0 AS calc_unitcost,
        0.0 AS calc_totalcost
        
        
    FROM
        invhist
    WHERE
        (invhist_transtype = 'SH' OR invhist_transtype = 'RS')
        AND 
        invhist_posted = true;
    GROUP BY
        invhist_ordnumber,
        invhist_itemsite_id 
        ;
            

ALTER TABLE invhist_sell
  OWNER TO admin;
GRANT ALL ON TABLE invhist_sell TO admin;
GRANT ALL ON TABLE invhist_sell TO xtrole;





CREATE OR REPLACE FUNCTION invhist_sell_qtybefore(int)
  RETURNS  numeric(18,6)  AS
$BODY$
DECLARE
  i_id ALIAS FOR $1;
  v_itemsite_id INTEGER;
  v_transdate timestamp with time zone;
  v_qty numeric(18,6) ;
  v_return numeric(18,6) ;
BEGIN
    v_return := 0;




   SELECT
      itemsite_id,
     transdate,
     qty
        INTO
        v_itemsite_id, 
        v_transdate 
         
        FROM invhist_sell
        WHERE
            invhist_id = i_id
        LIMIT 1;
   

-- # when transactions are the same day, we only want to include the ones with lower ids..


    SELECT   COALESCE(SUM( qty), 0)   INTO v_return 
        FROM invhist_sell 
        WHERE
            itemsite_id = v_itemsite_id
            AND   ( 
                transdate <  v_transdate 
                OR
                (transdate =  v_transdate AND invhist_id < i_id)
            )  ;

    IF (v_return IS NULL) THEN 
        v_return = 0;
    END IF;


 

  RETURN v_return;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION  invhist_sell_qtybefore(int)
  OWNER TO admin;


--------------- COGS CALC...
 
 
xtuplehk=# select *, invhist_sell_qtybefore(invhist_id) from invhist_sell where invhist_id = 53429  ;
 ordernumber | itemsite_id |    qty    | current_totalcost |   current_unitcost   | ordertype | invhist_id |       transdate        | invhist_sell_qtybefore 
-------------+-------------+-----------+-------------------+----------------------+-----------+------------+------------------------+------------------------
 3997-12     |        1149 | -60.000000 |          -8738.40 | 145.6400000000000000 | SH        |      53429 | 2010-02-26 00:00:00+08 |            -718.000000


Now to calculate FIFO VALUE..1149

select * ,invhist_buy_after(invhist_id) as qtyafter from invhist_buy
        where
            itemsite_id=1149
            AND
            invhist_buy_after(invhist_id) > 718.000000
            AND
            invhist_buy_after(invhist_id) <= 718.000000 + 60.000000
        
        ORDER BY
            transdate ASC, invhist_id ASC
        LIMIT 1;
        
        
ordernumber   | itemsite_id |    qty     | totalcost |       unitcost       | transtype | invhist_id |       transdate        |  qtyafter   
-----------------+-------------+------------+-----------+----------------------+-----------+------------+------------------------+-------------
BU0021/NV5675-2 |        1149 | 402.000000 |  58547.28 | 145.6400000000000000 | RP        |      36656 | 2011-08-09 00:00:00+08 | 1693.000000

STOCK UN-ALLOCATED (IN THIS ONE) = 1693.000000 - 1595.000000
 ==> 98 PIECES
 

TRIGGER INSERT UPDATE DELETE ON invhist
    
    UPDATE OR INSERT THE relivant invhist_buy or invhist_sell tables
    
    THEN RUN invhist_sell_qtybefore OR invhist_buy_after to fix the qtybefore qtyafter
    
    ON ALL ROWS AFTER
    THEN
    RUN THE FIFO CALC 
    

        


