-- Function: invreceipt(integer, numeric, text, text, text, timestamp with time zone, numeric)

-- DROP FUNCTION invreceipt(integer, numeric, text, text, text, timestamp with time zone, numeric);

CREATE OR REPLACE FUNCTION invreceipt(integer, numeric, text, text, text, timestamp with time zone, numeric)
  RETURNS integer AS
$BODY$
DECLARE
  pItemsiteid ALIAS FOR $1;
  pQty ALIAS FOR $2;
  pOrdernumber ALIAS FOR $3;
  pDocumentNumber ALIAS FOR $4;
  pComments ALIAS FOR $5;
  pGlDistTS     ALIAS FOR $6;
  pCostValue ALIAS FOR $7;
  
  _CostValueOwn numeric;
  
  _invhistid INTEGER;
  _itemlocSeries INTEGER;

BEGIN

--  Make sure the passed itemsite points to a real item
  IF ( ( SELECT (item_type IN ('R', 'F') OR itemsite_costmethod = 'J')
         FROM itemsite, item
         WHERE ( (itemsite_item_id=item_id)
          AND (itemsite_id=pItemsiteid) ) ) ) THEN
    RETURN 0;
  END IF;

  IF ( pQty > 0) THEN
    IF (pCostValue IS NULL) THEN
        RAISE EXCEPTION 'Cost value isn''t provided';
    END IF;
	_CostValueOwn := pCostValue;
  ELSIF (pQty < 0) THEN
    IF (pCostValue IS NOT NULL) THEN
        RAISE EXCEPTION 'Cost value hasn''t sense for such type of transaction';
    END IF;
    
    _CostValueOwn := itemcost_dispense(pItemsiteid, pQty);
  END IF;
  
  SELECT NEXTVAL('itemloc_series_seq') INTO _itemlocSeries;
  SELECT postInvTrans( itemsite_id, 'RX', pQty,
                       'I/M', 'RX', pDocumentNumber, '',
                       ('Miscellaneous Receipt for item ' || item_number || E'\n' ||  pComments),
                       costcat_asset_accnt_id, costcat_liability_accnt_id,
                       _itemlocSeries, pGlDistTS, _CostValueOwn) INTO _invhistid
  FROM itemsite, item, costcat
  WHERE ( (itemsite_item_id=item_id)
   AND (itemsite_costcat_id=costcat_id)
   AND (itemsite_id=pItemsiteid) );

  RETURN _itemlocSeries;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION invreceipt(integer, numeric, text, text, text, timestamp with time zone, numeric) OWNER TO "admin";
