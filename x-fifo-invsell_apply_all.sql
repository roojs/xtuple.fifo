CREATE OR REPLACE FUNCTION invsell_apply_all() RETURNS integer
AS $BODY$
DECLARE
    invsell_rec RECORD;
    
    v_totalcostbefore numeric(12, 2);
    v_mininvsell_transdate timestamp with time zone;
    
BEGIN

-- find all the matches that we can update, and make the changes.

-- updates invhist and gltrans
    PERFORM  
            invsell_apply(
                invsell_invhist_id,
                invhist_id
            ) as result
        FROM
            invhist
        INNER JOIN
            invdepend ON invhist_id = invdepend_invhist_id
        INNER JOIN
            invsell ON invdepend_parent_id = invsell_invhist_id
        
        WHERE
            invsell_current_totalcost  !=  invsell_calc_totalcost
            AND
            invsell_is_estimate = false;
    
-- updates invhist and itemsite.
    PERFORM
            invsell_apply_order (
                invsell_invhist_id
            ) as result
        FROM
            invsell
        WHERE
            invsell_current_totalcost  !=  invsell_calc_totalcost
            AND
            invsell_is_estimate = false;



    SELECT min(invsell_transdate)
            INTO v_mininvsell_transdate
            FROM invsell;


    PERFORM
            invsell_apply_trialbal (
                costcat_asset_accnt_id
            ) as result
        FROM
            invsell
        LEFT JOIN itemsite ON itemsite_id = invsell_itemsite_id
        LEFT JOIN costcat ON costcat_id = itemsite_costcat_id
        WHERE
            invsell_current_totalcost  !=  invsell_calc_totalcost
            AND
            invsell_is_estimate = false;
        
    PERFORM
            invsell_apply_trialbal (
                costcat_shipasset_accnt_id
            ) as result
        FROM
            invsell
        LEFT JOIN itemsite ON itemsite_id = invsell_itemsite_id
        LEFT JOIN costcat ON costcat_id = itemsite_costcat_id
        WHERE
            invsell_current_totalcost  !=  invsell_calc_totalcost
            AND
            invsell_is_estimate = false;
        
    PERFORM
            invsell_apply_trialbal (
                resolvecosaccount(invsell_itemsite_id, cohead_cust_id)
            ) as result
        FROM
            invsell
        LEFT JOIN cohead ON 
            cohead_number = CASE strpos(invsell_ordnumber, '-')
                        WHEN 0 THEN invsell_ordnumber 
                        ELSE substr(invsell_ordnumber, 1, strpos(invsell_ordnumber, '-') - 1)
                    END
        WHERE
            invsell_current_totalcost  !=  invsell_calc_totalcost
            AND
            invsell_is_estimate = false;
    RETURN 1;
            
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
  
ALTER FUNCTION  invsell_apply_all()
  OWNER TO admin;
