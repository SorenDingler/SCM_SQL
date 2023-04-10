with 

[Avg_1d_FC] as 
(Select ProductbusinessId, 
sum(isnull([Daily_Married_Forecast],0))/7 as [Avg_1d_FCST]
From [SNOP].[dbo].[SNOP_FCST_DAILY]
where [Calendar_Date] between convert(date,getdate()) and convert(date,getdate()+6) 
GROUP BY productbusinessid)
,

Visits as 
(
select SKU, sum(Visits_pro_sku) as Visits_pro_sku
from operationalflaconi.dbo.visitsProSKu 
where Visit_datum = convert(date,getdate()-1)
GROUP BY SKU)
,

Instock as 
(
Select QuantityInStock as QuantityInStock, 
wh.ProductBusinessID 
From operationalflaconi.[dbo].[Warehouse_History] wh
Where wh.snapshot_date = convert(date,getdate()-1))
,

--Menge in Auftrag
ON_order as 
(SELECT 
s.[ProductbusinessID]
,isnull(sum([QtyOnOrder]),0) as QtyOnOrder
FROM [OperationalFlaconi].[dbo].[SalesOrderLine] s
group by s.ProductBusinessID)
,


[Promo_EBE] as
(SELECT
       pl2.[Document No_] as EBE
    --,[Promo_ID]
    --,[Week_Start_Date]
    ,max([SKU_Uplift_percent]) as Uplift
  FROM [SNOP].[dbo].[SKU_uplift] su
  Left Join NBIS_FLA_STG.dbo.FLA_PurchaseLine pl2
  ON su.[productbusinessid] = pl2.[no_] 
  where datepart(iso_week,getdate()) in (datepart(iso_week,[Week_Start_Date]), datepart(iso_week,[Week_Start_Date])-1) and
  pl2.[Outstanding Quantity] <> 0
  group by
  pl2.[Document No_]
    --,[Promo_ID]
    --,[Week_Start_Date]
       )
,

--Restbestellmenge einer EBE über alle SKUs
OutstandingQtyEBE as
(select
pl3.[Document No_] as EBE,
convert(float,sum(pl3.[Outstanding Quantity])) as [Outstanding Quantity]
       FROM NBIS_FLA_STG.dbo.FLA_PurchaseLine pl3
       Group by pl3.[Document No_])
,


OOS_EBE as 
(Select 
pl.[Document No_] as EBE
,convert(float,sum(pl.[Outstanding Quantity])) as [Outstanding Quantity per SKU]
,convert(float,isnull(vi.Visits_pro_sku,0)) as Visits_pro_sku

from NBIS_FLA_STG.dbo.FLA_PurchaseLine pl
LEFT join visits vi
ON vi.SKu = pl.[No_]
LEFT JOIN instock ins
ON pl.[No_] = ins.[ProductbusinessID]
LEFT JOIN ON_order oo
ON oo.[ProductbusinessID] = pl.[No_]
LEFT JOIN [Avg_1d_FC] fc
ON fc.ProductbusinessId = pl.[No_]
LEFT JOIN [NBIS_FLA_STG].[dbo].[FLA_PurchaseHeader] ph
ON pl.[document no_]=ph.[no_]
WHERE [Outstanding Quantity] <> 0
and [Document No_] like 'EBE%'
AND QuantityInStock = 0
--and Case when convert(float,isnull([Avg_1d_FCST],0)) = 0 then 999 else (isnull(QuantityInStock,0)-isnull(0,oo.QtyOnOrder))/[Avg_1d_FCST] end < '1'
--and convert(date,ph.[Expected Receipt Date])<convert(date,getdate()+2)
GROUP BY 
pl.[Document No_], 
Visits_pro_sku)
,

[OOS_EBE_grouped] as

(select
EBE
,sum([Outstanding Quantity per SKU]) as [Outstanding Quantity per SKU]
,sum([visits_pro_sku]) as [visits_pro_sku]
from OOS_EBE 

group by 
EBE),


Basis as 
(select distinct EBE from [OOS_EBE_grouped]  -- hat dupletten
union
select distinct [EBE] as EBE  from [Promo_EBE]  -- keine dupletten
)

Select
row_number() over
(order by oeg.visits_pro_sku desc, pe.Uplift desc) as [Ranking],
b.EBE,
h.[Buy-from Vendor Name],
oeg.[Outstanding Quantity per SKU],
oeg.visits_pro_sku,
pe.Uplift,
ooe.[Outstanding Quantity] as [Outstanding Quantity EBE],
case 
       when cast(h.[Bestellstatus] as nvarchar) ='O' then 'Offen' 
             when cast(h.[Bestellstatus] as nvarchar) ='1' then 'Bearbeitung/Komplett eingebucht'
             when cast(h.[Bestellstatus] as nvarchar)='2' then 'Bestellung versendet'
                    when cast(h.[Bestellstatus] as nvarchar) ='3' then 'per EDI versendet'
                           when cast(h.[Bestellstatus] as nvarchar)='4' then 'Empfangen'
                                  else 'No Status' END as [Bestellstatus]
From Basis b
LEFT Join [OOS_EBE_grouped] oeg
ON b.ebe=oeg.EBE 
LEFT Join [Promo_EBE] pe
ON b.ebe= pe.ebe
Left Join [NBIS_FLA_STG].[dbo].[FLA_PurchaseHeader] h
ON b.ebe=h.[No_]
LEFT Join OutstandingQtyEBE ooe
ON b.ebe=ooe.EBE

Order by oeg.visits_pro_sku desc, pe.Uplift desc




