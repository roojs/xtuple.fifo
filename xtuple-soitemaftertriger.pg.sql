-- Function: _soitemaftertrigger()

-- DROP FUNCTION _soitemaftertrigger();

CREATE OR REPLACE FUNCTION _soitemaftertrigger()
  RETURNS trigger AS
$BODY$
DECLARE
  _check NUMERIC;
  _custID INTEGER;
  _po BOOLEAN;
  _kit BOOLEAN;
  _fractional BOOLEAN;
  _purchase BOOLEAN;
  _rec RECORD;
  _kstat TEXT;
  _pstat TEXT;
  _result INTEGER;
  _coitemid INTEGER;
  _itemsrcid INTEGER;
  _mustdelete INTEGER;
  _subnumber INTEGER;  

BEGIN

  IF(TG_OP = 'DELETE') THEN
    _rec := OLD;
  ELSE
    _rec := NEW;
  END IF;

  --Cache some information
  SELECT cohead_cust_id INTO _custID
  FROM cohead
  WHERE (cohead_id=_rec.coitem_cohead_id);

  --Determine if this is a kit for later processing
  SELECT COALESCE(item_type,'')='K', item_fractional
    INTO _kit, _fractional
    FROM itemsite, item
   WHERE((itemsite_item_id=item_id)
     AND (itemsite_id=_rec.coitem_itemsite_id));
  _kit := COALESCE(_kit, false);
  _fractional := COALESCE(_fractional, false);

 --Select purchase items
  SELECT COALESCE(item_type,'')='P'
    INTO _purchase
    FROM itemsite JOIN item ON (itemsite_item_id=item_id)
   WHERE (itemsite_id=_rec.coitem_itemsite_id);
  _purchase := COALESCE(_purchase, false);
 
 --Select salesorder related to purchaseorder 
  SELECT itemsite_createsopo INTO _po 
  FROM itemsite JOIN coitem ON  (itemsite_id=coitem_itemsite_id) 
  WHERE (coitem_id=_rec.coitem_id);

  IF (_kit) THEN
  -- Kit Processing
    IF (TG_OP = 'INSERT') THEN
  -- Create Sub Lines for Kit Components
      PERFORM explodeKit(NEW.coitem_cohead_id, NEW.coitem_linenumber, 0, NEW.coitem_itemsite_id,
                         NEW.coitem_qtyord, NEW.coitem_scheddate, NEW.coitem_promdate, NEW.coitem_memo);
      IF (fetchMetricBool('KitComponentInheritCOS')) THEN
  -- Update kit line item COS
        UPDATE coitem
        SET coitem_cos_accnt_id = CASE WHEN (COALESCE(NEW.coitem_cos_accnt_id, -1) != -1) THEN NEW.coitem_cos_accnt_id
                                       WHEN (NEW.coitem_warranty) THEN resolveCOWAccount(NEW.coitem_itemsite_id, _custID)
                                       ELSE resolveCOSAccount(NEW.coitem_itemsite_id, _custID)
                                  END
        WHERE((coitem_cohead_id=NEW.coitem_cohead_id)
          AND (coitem_linenumber = NEW.coitem_linenumber)
          AND (coitem_subnumber > 0));
      END IF;
    END IF;
    IF (TG_OP = 'UPDATE') THEN
    
    
      IF (NEW.coitem_qtyord <> OLD.coitem_qtyord) THEN
  -- Recreate Sub Lines for Kit Components
  
        
        SELECT explodeKitMustDelete(
        
            NEW.coitem_cohead_id, NEW.coitem_linenumber,
            0, NEW.coitem_itemsite_id
        ) INTO _mustdelete;
  
    
    
        FOR _coitemid IN
            SELECT coitem_id
                FROM coitem
                WHERE
                    (
                        (coitem_cohead_id=OLD.coitem_cohead_id)
                        AND
                        (coitem_linenumber=OLD.coitem_linenumber)
                        AND
                        (coitem_subnumber > 0)
                    )
        LOOP
        
          --SELECT deleteSoItem(_coitemid) INTO _result;
            IF (_mustdelete > 0) THEN
              SELECT deleteSoItem(_coitemid) INTO _result;
            ELSE
                -- if not delete, see if we could...
                BEGIN
                    SELECT deleteSoItemCheck(_coitemid) INTO _result;
                EXCEPTION WHEN OTHERS THEN
                    _result := 0;
                    RAISE NOTICE 'ok to delete';

                END;
            END IF;
            IF (_result < 0) THEN
               RAISE EXCEPTION 'Error deleting kit components: deleteSoItemCheck(integer) Error:%', _result;
            END IF;
            
        END LOOP;
            
            -- at this point we have not deleted anything..
            -- we have checked that it is feasible though..
            
            
        SELECT explodeKit(
        
                NEW.coitem_cohead_id, NEW.coitem_linenumber,
                0, NEW.coitem_itemsite_id,
                
                NEW.coitem_qtyord, NEW.coitem_scheddate,
                NEW.coitem_promdate
            ) INTO  _subnumber;
        
        IF (_mustdelete < 1) THEN
            -- if we where updating.. then trash all the extra lines..
            -- we can ignore results, as we know it will work based on the check above..
            PERFORM deleteSoItem(coitem_id) 
                FROM coitem
                WHERE
                    (
                        (coitem_cohead_id=OLD.coitem_cohead_id)
                        AND
                        (coitem_linenumber=OLD.coitem_linenumber)
                        AND
                        (coitem_subnumber > _subnumber)
                    );
        END IF;
        
                       
                             
                             
                           
      END IF;
      IF ( (NEW.coitem_qtyord <> OLD.coitem_qtyord) OR
           (NEW.coitem_cos_accnt_id <> OLD.coitem_cos_accnt_id) ) THEN
        IF (fetchMetricBool('KitComponentInheritCOS')) THEN
  -- Update kit line item COS
          UPDATE coitem
          SET coitem_cos_accnt_id = CASE WHEN (COALESCE(NEW.coitem_cos_accnt_id, -1) != -1) THEN NEW.coitem_cos_accnt_id
                                         WHEN (NEW.coitem_warranty) THEN resolveCOWAccount(NEW.coitem_itemsite_id, _custID)
                                         ELSE resolveCOSAccount(NEW.coitem_itemsite_id, _custID)
                                    END
          WHERE((coitem_cohead_id=NEW.coitem_cohead_id)
            AND (coitem_linenumber = NEW.coitem_linenumber)
            AND (coitem_subnumber > 0));
        END IF;
      END IF;
    END IF;
    IF (TG_OP = 'DELETE') THEN
  -- Delete Sub Lines for Kit Components
     FOR _coitemid IN
        SELECT coitem_id
        FROM coitem
        WHERE ( (coitem_cohead_id=OLD.coitem_cohead_id)
          AND   (coitem_linenumber=OLD.coitem_linenumber)
          AND   (coitem_subnumber > 0) )
      LOOP
        SELECT deleteSoItem(_coitemid) INTO _result;
        IF (_result < 0) THEN
           RAISE EXCEPTION 'Error deleting kit components: deleteSoItem(integer) Error:%', _result;
        END IF;
      END LOOP;
    END IF;
  END IF;

  IF (TG_OP = 'INSERT') THEN
    -- Create Purchase Order if flagged to do so
    IF ((NEW.coitem_order_type='P') AND (NEW.coitem_order_id=-1)) THEN
      SELECT itemsrc_id INTO _itemsrcid
      FROM itemsite JOIN itemsrc ON (itemsrc_item_id=itemsite_item_id AND itemsrc_default)
      WHERE (itemsite_id=NEW.coitem_itemsite_id);
      IF (FOUND) THEN
        SELECT createPurchaseToSale(NEW.coitem_id,
                                    _itemsrcid,
                                    itemsite_dropship,
                                    CASE WHEN (NEW.coitem_prcost=0.0) THEN NULL
                                         ELSE NEW.coitem_prcost
                                    END) INTO NEW.coitem_order_id
        FROM itemsite
        WHERE (itemsite_id=NEW.coitem_itemsite_id);
      END IF;
    END IF;
  END IF;

  IF (_purchase) THEN
    --For purchase item processing
--    IF (fetchmetricbool('EnableDropShipments')) THEN
--      --Dropship processing
      IF(_po) THEN
        IF (TG_OP = 'UPDATE') THEN
          IF ((NEW.coitem_qtyord <> OLD.coitem_qtyord) OR (NEW.coitem_qty_invuomratio <> OLD.coitem_qty_invuomratio) OR (NEW.coitem_scheddate <> OLD.coitem_scheddate)) THEN
            --Update related poitem
            UPDATE poitem
            SET poitem_qty_ordered = roundQty(_fractional, (NEW.coitem_qtyord * NEW.coitem_qty_invuomratio / poitem_invvenduomratio)),
                poitem_duedate = NEW.coitem_scheddate 
            WHERE (poitem_id = OLD.coitem_order_id);

            --Generate the PoItemUpdatedBySo event
            INSERT INTO evntlog
                        ( evntlog_evnttime, evntlog_username, evntlog_evnttype_id,
                          evntlog_ordtype, evntlog_ord_id, evntlog_warehous_id,
                          evntlog_number )
            SELECT CURRENT_TIMESTAMP, evntnot_username, evnttype_id,
              'P', poitem_id, itemsite_warehous_id,
            (pohead_number || '-'|| poitem_linenumber || ': ' || item_number)
            FROM evntnot JOIN evnttype ON (evntnot_evnttype_id=evnttype_id)
                 JOIN itemsite ON (evntnot_warehous_id=itemsite_warehous_id)
                 JOIN item ON (itemsite_item_id=item_id)
                 JOIN poitem ON (poitem_itemsite_id=itemsite_id)
                 JOIN pohead ON (poitem_pohead_id=pohead_id)
            WHERE( (poitem_id=OLD.coitem_order_id)
            AND (poitem_duedate <= (CURRENT_DATE + itemsite_eventfence))
            AND (evnttype_name='PoItemUpdatedBySo') );
          END IF;

          --If soitem is cancelled
          IF ((NEW.coitem_status = 'X') AND (OLD.coitem_status <> 'X')) THEN
            --Generate the PoItemSoCancelled event
            INSERT INTO evntlog
                        ( evntlog_evnttime, evntlog_username, evntlog_evnttype_id,
                          evntlog_ordtype, evntlog_ord_id, evntlog_warehous_id,
                          evntlog_number )
            SELECT CURRENT_TIMESTAMP, evntnot_username, evnttype_id,
            'P', poitem_id, itemsite_warehous_id,
            (pohead_number || '-' || poitem_linenumber || ': ' || item_number)
            FROM evntnot JOIN evnttype ON (evntnot_evnttype_id=evnttype_id)
                 JOIN itemsite ON (evntnot_warehous_id=itemsite_warehous_id)
                 JOIN item ON (itemsite_item_id=item_id)
                 JOIN poitem ON (poitem_itemsite_id=itemsite_id)
            JOIN pohead ON( poitem_pohead_id=pohead_id)
            WHERE( (poitem_id=OLD.coitem_order_id)
            AND (poitem_duedate <= (CURRENT_DATE + itemsite_eventfence))
            AND (evnttype_name='PoItemSoCancelled') );
          END IF;
        END IF;
      END IF; 
--    END IF;
  END IF;

  IF (_rec.coitem_subnumber > 0) THEN
    SELECT coitem_status
      INTO _kstat
      FROM coitem
     WHERE((coitem_cohead_id=_rec.coitem_cohead_id)
       AND (coitem_linenumber=_rec.coitem_linenumber)
       AND (coitem_subnumber = 0));
    IF ((SELECT count(*)
           FROM coitem
          WHERE((coitem_cohead_id=_rec.coitem_cohead_id)
            AND (coitem_linenumber=_rec.coitem_linenumber)
            AND (coitem_subnumber <> _rec.coitem_subnumber)
            AND (coitem_subnumber > 0)
            AND (coitem_status = 'O'))) > 0) THEN
      _pstat := 'O';
    ELSE
      _pstat := _rec.coitem_status;
    END IF;
  END IF;

  IF(TG_OP = 'INSERT') THEN
    IF (_rec.coitem_subnumber > 0 AND _rec.coitem_status = 'O') THEN
      _pstat := 'O';
    END IF;
  ELSIF (TG_OP = 'UPDATE') THEN
    IF (_rec.coitem_subnumber > 0 AND _rec.coitem_status = 'O') THEN
      _pstat := 'O';
    END IF;

    IF ((NEW.coitem_status = 'C') AND (OLD.coitem_status <> 'C')) THEN
      IF(_kit) THEN
        UPDATE coitem
           SET coitem_status='C'
         WHERE((coitem_cohead_id=OLD.coitem_cohead_id)
           AND (coitem_linenumber=OLD.coitem_linenumber)
           AND (coitem_status='O')
           AND (coitem_subnumber > 0));
      END IF;
    END IF;

    IF ((NEW.coitem_status = 'X') AND (OLD.coitem_status <> 'X')) THEN
      IF(_kit) THEN
        UPDATE coitem
           SET coitem_status='X'
         WHERE((coitem_cohead_id=OLD.coitem_cohead_id)
           AND (coitem_linenumber=OLD.coitem_linenumber)
           AND (coitem_status='O')
           AND (coitem_subnumber > 0));
      END IF;
    END IF;

    IF(NEW.coitem_status = 'O' AND OLD.coitem_status <> 'O') THEN
      IF(_kit) THEN
        UPDATE coitem
           SET coitem_status='O'
         WHERE((coitem_cohead_id=OLD.coitem_cohead_id)
           AND (coitem_linenumber=OLD.coitem_linenumber)
           AND ((coitem_qtyord - coitem_qtyshipped + coitem_qtyreturned) > 0)
           AND (coitem_subnumber > 0));
      END IF;
    END IF;

  END IF;

  IF ((_kstat IS NOT NULL) AND (_pstat IS NOT NULL) AND (_rec.coitem_subnumber > 0) AND (_kstat <> _pstat)) THEN
    UPDATE coitem
       SET coitem_status = _pstat
     WHERE((coitem_cohead_id=_rec.coitem_cohead_id)
       AND (coitem_subnumber = 0));
  END IF;

  IF(TG_OP = 'DELETE') THEN
    RETURN OLD;
  END IF;

  --If auto calculate freight, recalculate cohead_freight
  IF (SELECT cohead_calcfreight FROM cohead WHERE (cohead_id=NEW.coitem_cohead_id)) THEN
    UPDATE cohead SET cohead_freight = COALESCE(
      (SELECT SUM(freightdata_total) FROM freightDetail('SO',
                                                        cohead_id,
                                                        cohead_cust_id,
                                                        cohead_shipto_id,
                                                        cohead_orderdate,
                                                        cohead_shipvia,
                                                        cohead_curr_id)), 0)
    WHERE cohead_id=NEW.coitem_cohead_id;
  END IF;

  RETURN NEW;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION _soitemaftertrigger()
  OWNER TO admin;
