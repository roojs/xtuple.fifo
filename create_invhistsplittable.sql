CREATE SEQUENCE invhistsplit_invhistsplit_id_seq
  INCREMENT 1
  MINVALUE 1
  MAXVALUE 2147483647
  START 4120
  CACHE 1;

create table invhistsplit (
	invhistsplit_id integer NOT NULL DEFAULT nextval(('invhistsplit_invhistsplit_id_seq'::text)::regclass),
	invhistsplit_qty numeric(12, 2) NOT NULL,
	invhistsplit_unitcost   numeric(12, 2) DEFAULT 0,
	invhistsplit_totalcost   numeric(12, 2) DEFAULT 0,
	invhistsplit_reverse_id  integer,
	invhistsplit_itemsite_id integer,
	invhistsplit_dt timestamp with time zone NOT NULL DEFAULT now(),
	invhistsplit_invhist_id integer,
	invhistsplit_estimated boolean,
	CONSTRAINT invhistsplit_pkey PRIMARY KEY (invhistsplit_id),
	CONSTRAINT invhistsplit_invhist_fk FOREIGN KEY (invhistsplit_invhist_id) REFERENCES invhist (invhist_id),
	CONSTRAINT invhistsplit_reverse_fk FOREIGN KEY (invhistsplit_reverse_id) REFERENCES invhistsplit (invhistsplit_id) MATCH SIMPLE,
	CONSTRAINT invhistsplit_itemsite_fk FOREIGN KEY (invhistsplit_itemsite_id) REFERENCES itemsite (itemsite_id)
);

CREATE INDEX invhistsplit_qty_indx
  ON invhistsplit
  USING btree
  (invhistsplit_qty);

CREATE INDEX invhistsplit_itemsite_id_indx
  ON invhistsplit
  USING btree
  (invhistsplit_itemsite_id);

CREATE INDEX invhistsplit_dt_indx
  ON invhistsplit
  USING btree
  (invhistsplit_dt);	

CREATE INDEX invhistsplit_invhist_id_indx
  ON invhistsplit
  USING btree
  (invhistsplit_invhist_id);
  

