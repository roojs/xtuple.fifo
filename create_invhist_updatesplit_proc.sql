CREATE OR REPLACE FUNCTION invhist_updatesplit(integer, date)
  RETURNS boolean AS
$BODY$
DECLARE
  -- Variable naming :  i_ = INPUT,  v_ = Variables
  i_itemsite_id         ALIAS FOR $1;
  i_date                ALIAS FOR $2;
  v_remaining           numeric(12, 2);
  v_cost                numeric(12, 2);
  v_allocate            numeric(12, 2);
  
  
  findincome_c CURSOR FOR 
			  SELECT
				 invhistsplit_id, invhistsplit_qty, invhistsplit_unitcost,
				 invhistsplit_totalcost, invhistsplit_reverse_id, invhistsplit_itemsite_id,
				 invhistsplit_dt, invhistsplit_invhist_id, invhistsplit_estimated 
			  FROM invhistsplit 
			  WHERE 
					invhistsplit_itemsite_id = i_itemsite_id
					AND 
					invhistsplit_qty > 0 
					AND 
					invhistsplit_reverse_id IS NULL
			  ORDER by invhistsplit_dt ASC
			  FOR UPDATE;
			  

  outgoins RECORD;
  incoming RECORD;

BEGIN 

-- Lock table invhistsplit as for so no other entities can make changes
	LOCK TABLE invhistsplit IN EXCLUSIVE MODE;
	
-- unallocate incomming stock that was allocated to outgoing transactions after our specified date.

	UPDATE invhistsplit SET invhistsplit_reverse_id = NULL WHERE 
		invhistsplit_reverse_id IN ( 
			SELECT invhistsplit_id FROM invhistsplit
				WHERE 
					invhistsplit_itemsite_id = i_itemsite_id 
					and
					invhistsplit_dt >= i_date
		);
		
-- this could be done more effeciently.
-- DELETE incomming  after that date.
-- UPDATE outgoing  after that date reverse_id=NULL, 0 unitcost=0 and totalvalue=0 into outgoing after this date.
-- then just insert incomming.
-- This has the downside that we need to check for new 'outgoing' somewhere as they would not get automatically added
-- So for the time being we are keeping with our existing logic here.



	DELETE FROM invhistsplit 
		WHERE 
			invhistsplit_itemsite_id = i_itemsite_id 
			and
			invhistsplit_dt >= i_date;



		
	insert into invhistsplit  (
			invhistsplit_qty,  
			invhistsplit_unitcost,

			invhistsplit_totalcost, 
			invhistsplit_reverse_id, 

			invhistsplit_itemsite_id, invhistsplit_dt, 
			invhistsplit_invhist_id, invhistsplit_estimated
	) select 
			(invhist_qoh_after - invhist_qoh_before) qty, 
			case 
				when (invhist_qoh_after - invhist_qoh_before) > 0 and invhist_posted 
					then invhist_unitcost
				else 0
					end unitcost,

			case
				 when (invhist_qoh_after - invhist_qoh_before) > 0 and invhist_posted 
					then invhist_value_after - invhist_value_before 
				else 0
					end totalvalue,
			NULL,
		 	invhist_itemsite_id, invhist_transdate,
			invhist_id, false
		from invhist 
			where invhist_itemsite_id = i_itemsite_id and invhist_transdate >= i_date;

			
	FOR outgoins IN

		SELECT 
			invhistsplit_id, invhistsplit_qty, invhistsplit_dt 	
		FROM invhistsplit 
		WHERE
			 invhistsplit_itemsite_id = i_itemsite_id 
			AND 
			invhistsplit_qty < 0 
			AND 
			invhistsplit_reverse_id IS NULL
		ORDER by invhistsplit_dt ASC
		

	LOOP
-- This is the loop for the outgoing.
-- at this point outgoins contains the information we want to allocate.

-- remaining is a -ve number... 
		v_remaining   := outgoins.invhistsplit_qty;
		v_cost        := 0;

-- run the query to look for available stock.
		OPEN findincome_c;
 

		WHILE v_remaining < 0 LOOP
			
			
 
			FETCH findincome_c INTO incoming;

-- If no more stock is available, give up trying to allocate stuff..
			IF NOT FOUND THEN 
				EXIT; 
			END IF;

 

				
			IF incoming.invhistsplit_qty < -v_remaining THEN 
-- If not enough stock in incomming, just allocate that

				v_allocate := incoming.invhistsplit_qty;
			ELSE	
-- Otherwise allocate all of it..
				v_allocate := -v_remaining;
			END IF;
		
			v_cost :=         v_cost +  (v_allocate *   incoming.invhistsplit_unitcost);
			v_remaining :=    v_remaining + v_allocate;



			--LOCK TABLE invhistsplit IN EXCLUSIVE MODE;
			IF v_allocate = incoming.invhistsplit_qty THEN
-- all of incomming stock is used by outgoing..
				UPDATE invhistsplit SET
					invhistsplit_reverse_id = outgoins.invhistsplit_id
				WHERE CURRENT OF findincome_c;

			ELSE
-- only some of the incomming stock is used
-- this inserts a new record of the used values
				INSERT INTO  invhistsplit (
						invhistsplit_qty, invhistsplit_unitcost, 
						invhistsplit_totalcost, invhistsplit_reverse_id, 
						invhistsplit_itemsite_id, invhistsplit_dt, 
						invhistsplit_invhist_id, invhistsplit_estimated
				) VALUES (
						v_allocate, incoming.invhistsplit_unitcost,
						v_allocate * incoming.invhistsplit_unitcost, outgoins.invhistsplit_id,
						incoming.invhistsplit_itemsite_id, incoming.invhistsplit_dt,
		    incoming.invhistsplit_invhist_id, false   
				);

				UPDATE invhistsplit SET
					invhistsplit_qty = invhistsplit_qty - v_allocate,
					invhistsplit_totalcost = invhistsplit_totalcost - v_allocate * incoming.invhistsplit_unitcost
				WHERE CURRENT OF findincome_c;
			END IF;
		
		END LOOP;
 
		UPDATE invhistsplit SET
			invhistsplit_unitcost = v_cost / abs(outgoins.invhistsplit_qty - v_remaining),
			invhistsplit_totalcost = CASE 
                                        WHEN v_remaining < 0 
                                                THEN invhistsplit_unitcost *  abs(outgoins.invhistsplit_qty)
                                                ELSE invhistsplit_totalcost END,
			invhistsplit_estimated = CASE WHEN v_remaining < 0 THEN true ELSE false END

		WHERE 
			invhistsplit_id = outgoins.invhistsplit_id;

		CLOSE findincome_c;
		
	END LOOP;

	
	-- UNLOCK HERE AUTOMATICALLY

    RETURN TRUE;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

