WITH [Product] AS (
SELECT PRODUCT_ID
, EAN
,PRODUCT_NAME
,CONVERT(DATE, AVAILABLE_AGAIN_FROM) AS AVAILABLE_AGAIN_FROM
,DIVISION_ID
,QUANTITY_INSTOCK AS Lagerbestand
, MANUFACTURER_ITEM_NO
FROM DM_SALES.DIM_PRODUCT
WHERE QUANTITY_INSTOCK <= '0'
AND PRODUCT_STATUS IN ('Basis','Limitiert')
	--AND product_id= '40900004'
)
,

[Menge_in_Bestellung] AS
(
SELECT
dm_p.product_id
,dm_pur.PURCHASE_ID
,dm_pur.PURCHASE_ORDER_DATE
,dm_pur.EXPECTED_RECEIPT_DATE
,dm_pur.ORDER_TYPE
,sum(dm_pur.outstanding_quantity) AS outstanding_quantity_external
FROM DM_SALES.FACT_PURCHASE dm_pur
LEFT JOIN DM_SALES.DIM_PRODUCT dm_p
ON dm_pur.PRODUCT_SKEY = dm_p.PRODUCT_SKEY
GROUP BY 
dm_p.product_id
,dm_pur.PURCHASE_ID
,dm_pur.PURCHASE_ORDER_DATE
,dm_pur.EXPECTED_RECEIPT_DATE
,dm_pur.ORDER_TYPE
)
,
Order_type_Base
	AS
	(
	SELECT
	PURCHASE_RECEIPT_ID
	,ORDER_TYPE
	FROM DM_SALES.FACT_PURCHASE
	)
	,
[OUTSTANDING_QUANTITY_intern] AS
	(
	SELECT
	ile.ITEM_NO
	,convert(decimal(18,2),sum(ile.REMAINING_QUANTITY)) AS Outstanding_Quantity_internal
	FROM STAGE_NAVISION.FLA_ITEM_LEDGER_ENTRY ile
	LEFT JOIN Order_type_Base orb
	ON ile.DOCUMENT_NO=orb.PURCHASE_RECEIPT_ID
	WHERE 
	ile.LOCATION_CODE='MARK_WE'
	AND ile.REMAINING_QUANTITY>0
	AND ile.delete_flag='false'
	AND ile.ENTRY_TYPE='0'
	AND orb.ORDER_TYPE NOT LIKE '%AKT%'
	AND orb.ORDER_TYPE NOT LIKE '%GWP%'
	GROUP BY
	ile.ITEM_NO
	)
	,
[Division] AS 
(SELECT 
NO_
,sat_ven.NAME
FROM RAW_VAULT.HUB_NAV_VENDOR_DIVISION hub_ven
LEFT JOIN RAW_VAULT.SAT_NAV_VENDOR_DIVISION sat_ven
ON hub_ven.VENDOR_DIVISION_HASHKEY = sat_ven.VENDOR_DIVISION_HASHKEY
WHERE sat_ven.DELETE_FLAG ='false'
AND sat_ven.VALID_TO > '9999-12-31'
)
,
UnitsYTD AS										
	(										
	/*Total Sold Qty YTD for Basis and Limitiert SKUs*/										
	SELECT										
	dm_p.product_id										
	,ifnull(round(sum(dm_s.QUANTITY)),0) AS Sold_Qty_YTD										
	FROM DM_SALES.FACT_SALES dm_s										
	LEFT JOIN DM_SALES.DIM_PRODUCT dm_p										
	ON dm_s.PRODUCT_SKEY = dm_p.product_skey										
	WHERE										
	dm_s.ORDER_DATE BETWEEN '2018-01-01' AND convert(DATE, now())
	GROUP BY										
	dm_p.product_id										
)
,
[SKU_Cluster_Base] AS										
	(
	SELECT
	dm_p.product_id										
	,dm_p.PRODUCT_STATUS										
	,ifnull(uytd.Sold_Qty_YTD,0) AS Sold_Qty_YTD
	FROM DM_SALES.DIM_PRODUCT dm_p
	LEFT JOIN [Menge_in_Bestellung] mb
	ON dm_p.PRODUCT_ID=mb.product_id
	LEFT JOIN [OUTSTANDING_QUANTITY_intern] oqi
	ON dm_p.PRODUCT_ID=oqi.ITEM_NO
	LEFT JOIN UnitsYTD uytd										
	ON dm_p.PRODUCT_ID=uytd.product_id	
	WHERE
	(
	(dm_p.PRODUCT_STATUS  LIKE '%Basis%' OR dm_p.PRODUCT_STATUS  LIKE '%Limitiert%' OR dm_p.PRODUCT_STATUS  LIKE '%Ex%' OR dm_p.PRODUCT_STATUS  LIKE '%OneShot%')
	AND convert(DATE,dm_p.RELEASE_DATE) <= convert(DATE,now())
	AND dm_p.SHOP_ACTIVITY_STATUS='activated'
	AND dm_p.SHOP_ACTIVITY_STATUS_CONFIG='activated'
	AND dm_p.SHOP_VISIBILITY='Einzeln nicht sichtbar'
	AND dm_p.SHOP_VISIBILITY_CONFIG='Katalog, Suche'
	)
	OR
	(
	(dm_p.PRODUCT_STATUS  LIKE '%Basis%' OR dm_p.PRODUCT_STATUS  LIKE '%Limitiert%' OR dm_p.PRODUCT_STATUS  LIKE '%Ex%' OR dm_p.PRODUCT_STATUS  LIKE '%OneShot%')
	AND convert(DATE,dm_p.RELEASE_DATE) <= convert(DATE,now())
	AND (ifnull(dm_p.QUANTITY_INSTOCK,0)+ifnull(outstanding_quantity_external,0)+ifnull(outstanding_quantity_internal,0)) > 0)
	)
,
[ABC_Clustering] AS 										
	(										
	/*ABC Clustering and connection to XYZ-Clustering [see above]*/										
	SELECT										
	scb.product_id										
	,scb.PRODUCT_STATUS										
	,scb.Sold_Qty_YTD										
	,sum(scb.Sold_Qty_YTD) OVER (ORDER BY scb.Sold_Qty_YTD DESC) AS CumulativeSales_YTD										
	,sum(scb.Sold_Qty_YTD) OVER () AS Total_Sales_YTD										
	,sum(scb.Sold_Qty_YTD) OVER (ORDER BY scb.Sold_Qty_YTD DESC) / sum(ifnull(scb.Sold_Qty_YTD,0)) OVER () AS CumulativePercentage_YTD										
	,CASE 										
		WHEN sum(scb.Sold_Qty_YTD) OVER (ORDER BY scb.Sold_Qty_YTD DESC) / sum(ifnull(scb.Sold_Qty_YTD,0)) OVER () <=0.5382									
			THEN 'A'								
		WHEN sum(scb.Sold_Qty_YTD) OVER (ORDER BY scb.Sold_Qty_YTD DESC) / sum(ifnull(scb.Sold_Qty_YTD,0)) OVER () <=0.8005									
			THEN 'B'								
		WHEN sum(scb.Sold_Qty_YTD) OVER (ORDER BY scb.Sold_Qty_YTD DESC) / sum(ifnull(scb.Sold_Qty_YTD,0)) OVER () <=0.9479									
			THEN 'C'								
		ELSE 'D' END AS turnover_rate_cluster									
	FROM [SKU_Cluster_Base] scb										
	GROUP BY										
	scb.product_id										
	,scb.PRODUCT_STATUS										
	,scb.Sold_Qty_YTD										
	)
	,
	[OUTSTANDING_QUANTITY_intern] AS
	(
	SELECT
	ile.ITEM_NO
	,convert(decimal(18,2),sum(ile.REMAINING_QUANTITY)) AS Outstanding_Quantity_internal
	FROM STAGE_NAVISION.FLA_ITEM_LEDGER_ENTRY ile
	LEFT JOIN Order_type_Base orb
	ON ile.DOCUMENT_NO=orb.PURCHASE_RECEIPT_ID
	WHERE 
	ile.LOCATION_CODE='MARK_WE'
	AND ile.REMAINING_QUANTITY>0
	AND ile.delete_flag='false'
	AND ile.ENTRY_TYPE='0' --=Einkauf
	AND orb.ORDER_TYPE NOT LIKE '%GWP%'
	GROUP BY
	ile.ITEM_NO
	)
	,
	[Oldest_PO_Min] as
	(
	SELECT
	dm_pro.PRODUCT_ID AS SKU
	,min(dm_pur.PURCHASE_ID) AS EBE
	FROM DM_SALES.FACT_PURCHASE dm_pur
	LEFT JOIN DM_SALES.DIM_PRODUCT dm_pro
	ON dm_pur.PRODUCT_SKEY = dm_pro.PRODUCT_SKEY
	WHERE OUTSTANDING_QUANTITY >0
	AND PURCHASE_STATUS NOT IN ('5','6')
	AND dm_pur.ORDER_TYPE NOT LIKE '%AKT%'
	GROUP BY
	dm_pro.PRODUCT_ID
	)
	,
--Schnittmenge aus DM_SALES.FACT_PURCHASE und [Oldest_PO_Min] ueber SKU und MIN_EBE
[Oldest_PO_Result] AS 
(
SELECT
dm_pro.PRODUCT_ID
,opo.EBE
,dm_pur.ORDER_TYPE
,dm_pur.PURCHASE_STATUS AS Delivery_Status
,ifnull(sum(OUTSTANDING_QUANTITY),0) AS  Open_Qty_oldest_PO
,convert(DATE,dm_pur.PURCHASE_ORDER_DATE) AS ORDER_date_oldest_PO
FROM DM_SALES.FACT_PURCHASE dm_pur
LEFT JOIN DM_SALES.DIM_PRODUCT dm_pro
ON dm_pur.PRODUCT_SKEY = dm_pro.PRODUCT_SKEY
INNER Join [Oldest_PO_Min] opo
ON opo.EBE = dm_pur.PURCHASE_ID
AND opo.SKU = dm_pro.PRODUCT_ID
WHERE
OUTSTANDING_QUANTITY >0
AND ORDER_TYPE NOT LIKE '%GWP%'
GROUP BY
dm_pro.PRODUCT_ID
,opo.[EBE]
,dm_pur.PURCHASE_STATUS
,PURCHASE_ORDER_DATE
,dm_pur.ORDER_TYPE
)
,

	[Oldest_PO_Min_Internal] as
(
SELECT
	dm_pro.PRODUCT_ID AS SKU
	,min(dm_pur.PURCHASE_ID) AS EBE
	FROM DM_SALES.FACT_PURCHASE dm_pur
	LEFT JOIN DM_SALES.DIM_PRODUCT dm_pro
	ON dm_pur.PRODUCT_SKEY = dm_pro.PRODUCT_SKEY
	WHERE OUTSTANDING_QUANTITY >0
	AND dm_pur.ORDER_TYPE NOT LIKE '%AKT%'
	AND PURCHASE_STATUS = '6'
	GROUP BY
	dm_pro.PRODUCT_ID
	)
	,
	[Leadtime] AS (
	SELECT 
	DIVISION_ID
	,BOOKING_LT_AVG
	FROM TMP_BUSINESS_LOGICS.SUPPLIER_LEADTIME
	WHERE JAHR='2018'
	)
	,
	[Oldest_PO_Result_internal] AS 
	(
	SELECT
	dm_pro.PRODUCT_ID
	,opo.EBE
	,dm_pur.ORDER_TYPE
	,dm_pur.PURCHASE_STATUS AS Delivery_Status
	,convert(DATE,dm_pur.PURCHASE_ORDER_DATE) AS ORDER_date_oldest_PO
	--, CASE WHEN opo.EBE = 'NULL' THEN 'NULL' ELSE CONVERT(DATE, PURCHASE_ORDER_DATE) + l.BOOKING_LT_AVG END AS Lieferdatum_O_EBE_EX
	FROM DM_SALES.FACT_PURCHASE dm_pur
	LEFT JOIN DM_SALES.DIM_PRODUCT dm_pro
	ON dm_pur.PRODUCT_SKEY = dm_pro.PRODUCT_SKEY
	INNER Join [Oldest_PO_Min_Internal] opo
	ON opo.EBE = dm_pur.PURCHASE_ID
	AND opo.SKU = dm_pro.PRODUCT_ID
	LEFT JOIN DM_SALES.DIM_DIVISION divi
	ON dm_pur.DIVISION_SKEY = divi.DIVISION_SKEY
	LEFT JOIN [Leadtime] l
	ON divi.DIVISION_ID = l.DIVISION_ID 
	WHERE
	OUTSTANDING_QUANTITY >0
	AND ORDER_TYPE NOT LIKE '%GWP%'
	AND PURCHASE_STATUS = '6'
	GROUP BY
	dm_pro.PRODUCT_ID
	,opo.[EBE]
	,dm_pur.PURCHASE_STATUS
	,dm_pur.PURCHASE_ID
	,PURCHASE_ORDER_DATE
	,EXPECTED_RECEIPT_DATE
	,dm_pur.ORDER_TYPE
	,(CONVERT(DATE, PURCHASE_ORDER_DATE) + l.BOOKING_LT_AVG)
	)
, 
[Zero_Order_Delivery] as
(
SELECT
pl.NO_ as [SKU]
,pl.DOCUMENT_NO as EBE
,max(pl.VERSION_NO) AS Aktuelle_Version
FROM STAGE_NAVISION.FLA_PURCHASE_LINE_ARCHIVE pl
LEFT JOIN STAGE_NAVISION.FLA_PURCHASE_HEADER_ARCHIVE ph
ON ph."NO" = pl.DOCUMENT_NO
WHERE ph.ORDER_DATE BETWEEN now()-60 and now()
AND ph.DELETE_FLAG= FALSE
AND pl.DELETE_FLAG = FALSE
GROUP BY pl.DOCUMENT_NO
,pl.DOCUMENT_NO
,pl.NO_
)
,
[ONLY_MAX_VERSIONS] AS
(
SELECT 
zero.SKU
,zero.EBE AS EBE
, pl.QUANTITY
FROM [Zero_Order_Delivery] zero
LEFT JOIN STAGE_NAVISION.FLA_PURCHASE_LINE_ARCHIVE pl
ON pl.NO_ = zero.sku AND pl.DOCUMENT_NO = zero.ebe AND pl.VERSION_NO = zero.Aktuelle_Version
WHERE pl.QUANTITY <= 0
)
,
[Anzahl_Zero_Orders] AS (
SELECT
dim.PRODUCT_ID
,count(ma.EBE) AS Zero_ORDER_Delivery
FROM DM_SALES.DIM_PRODUCT dim
LEFT JOIN [ONLY_MAX_VERSIONS] ma
ON dim.PRODUCT_ID = ma.[SKU]
GROUP BY
dim.PRODUCT_ID
)
,
Last7days AS										
	(																			
	SELECT										
	dm_p.product_id										
	,ifnull(round(sum(dm_s.QUANTITY)),0) AS Sold_Qty_7days										
	FROM DM_SALES.FACT_SALES dm_s										
	LEFT JOIN DM_SALES.DIM_PRODUCT dm_p										
	ON dm_s.PRODUCT_SKEY = dm_p.product_skey										
	WHERE										
	dm_s.ORDER_DATE BETWEEN now()-8 AND now()										
	GROUP BY										
	dm_p.product_id										
	)
	,
[SNOP_FCST7] AS (
SELECT PRODUCT_ID
, sum(SNOP_DAILY_FORECAST) AS FCST_7days 
FROM TMP_BUSINESS_LOGICS.V_SNOP_DAILY_FORECAST
WHERE CALENDAR_DATE BETWEEN now() and now()+6
GROUP BY PRODUCT_ID
)
,
OOS_Visits AS (
SELECT v.PRODUCT_ID
,sum(OOS_VISITS) AS OOS_Visits
FROM TMP_BUSINESS_LOGICS.VISITS_PER_SKU v
WHERE VISIT_DATE = now()-1
GROUP BY v.PRODUCT_ID
)
SELECT
DISTINCT p.PRODUCT_ID   
, abc.turnover_rate_cluster
, code.EK_CODE
, p.EAN
, MANUFACTURER_ITEM_NO
, p.PRODUCT_NAME
, CASE WHEN CONVERT(DATE, p.AVAILABLE_AGAIN_FROM)='1753-01-01' OR CONVERT(DATE, p.AVAILABLE_AGAIN_FROM) < now() THEN '[Available]' ELSE CONVERT(DATE, p.AVAILABLE_AGAIN_FROM) END AS Available_again_from
, p.DIVISION_ID
, di.Supplier_Name
, a.Zero_ORDER_Delivery
, opo.EBE AS oldest_EBE_external
, CONVERT(DATE, opo.ORDER_date_oldest_PO) + l.BOOKING_LT_AVG AS Lieferdatum_O_EBE_EX
, opoi.EBE AS oldest_EBE_internal
, IFNULL(la.Sold_Qty_7days,0) AS Sold_Units_7days
, snop.FCST_7days AS FCST_7days
, ROUND(oos.OOS_Visits) AS OOS_Visits_Yesterday
FROM [Product] p
LEFT JOIN [ABC_Clustering] abc
ON p.PRODUCT_ID = abc.PRODUCT_ID
LEFT JOIN [Anzahl_Zero_Orders] a
ON p.PRODUCT_ID = a.PRODUCT_ID
LEFT JOIN [Menge_in_Bestellung] m
ON p.PRODUCT_ID = m.product_id
LEFT JOIN [Leadtime] l
ON p.DIVISION_ID = l.DIVISION_ID
LEFT JOIN DM_SALES.DIM_DIVISION di
ON p.DIVISION_ID = di.Division_ID
LEFT JOIN [Oldest_PO_Result] opo
ON p.PRODUCT_ID = opo.product_id
LEFT JOIN [Oldest_PO_Result_internal] opoi
ON p.PRODUCT_ID = opoi.product_id
LEFT JOIN Last7days la
ON p.PRODUCT_ID = la.product_ID
LEFT JOIN [SNOP_FCST7] snop
ON p.PRODUCT_ID = snop.PRODUCT_ID
LEFT JOIN TEST_SANDBOX.DIVISION_EK_CODE code
ON p.DIVISION_ID = code."Division_ID"
LEFT JOIN OOS_Visits oos
ON p.PRODUCT_ID = oos.PRODUCT_ID
WHERE abc.turnover_rate_cluster IN ('A','B')
--AND p.product_id= '80027307-50'