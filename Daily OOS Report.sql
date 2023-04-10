WITh 
T as (SELECT [Item No_], MAX([Ending Date]) as second_price_date
FROm NBIS_FLA_STG.dbo.FLA_SalesPrice
GROUP BY [Item No_])


,Unitprice as(
SELECT t.[Item No_], [Unit Price] FROM  NBIS_FLA_STG.dbo.FLA_SalesPrice sp
Inner JOIN T 
ON sp.[Item No_] = T.[Item No_] and sp.[Ending Date] = T.second_price_date)
 

,Anlieferquote as (SELECT 
No_,
sum(Quantity)/SUM(CASE WHEN [Quantity expected] = 0  THEN Quantity +0.00001 ELSE [Quantity expected]+0.000001 END) as Anlieferquote  
FROM [NBIS_FLA_STG].[dbo].[FLA_PurchASeLine] 
WHERE [outstanding quantity] = 0
and [Quantity expected] < 99999
and [Order Date] >= (getdate() - 90)
--and [Buy-from Division No_] = 'PUG001'
--and [No_] = '80010912-50'
Group by No_	 
)

,minEBE AS
( SELECT  
alibaba.[No_]
, Min(alibaba.[Document No_]) [Document No_]
FROM NBIS_FLA_STG.dbo.FLA_PurchaseLine alibaba
WHERE  [Outstanding quantity] > 0
--AND alibaba.[No_] = '80008240-200'
GROUP BY alibaba.[No_])

,lastEBE as
(SELECT   

convert(date,ph.[Order Date]) as [Order Date]
,alibaba.[No_] as productbusinessid
FROM NBIS_FLA_STG.dbo.FLA_PurchaseLine alibaba
INNER JOIN minEBE 
ON minEBE.[Document No_] = alibaba.[Document No_] AND alibaba.[No_] = minEBE.[No_]
LEFT JOIN NBIS_FLA_STG.dbo.FLA_PurchaseHeader ph
ON alibaba.[Document No_] = ph.[No_]
WHERE [Outstanding quantity] > 0
AND Amount > 0
 --AND alibaba.[No_] = '80008240-200'
 )

 , Lieferzeit as
 (select * from operationalflaconi.otti.leadtime)

 , Uplifts as
 (SELECT * from SNOP.dbo.BaseCalcSNOP
WHERE Week_Start_Date = (SELECT Distinct Begin_of_Week from OperationalFlaconi.dbo.Calendar
where GETDATE()-1 between Begin_of_Week and [End_ of_Week]))

, UnitsL7days as
(Select ProductBusinessID,
sum(Invoiced_qty_aD_aR) as [Units l7d]
From operationalflaconi.dbo.management_report_daily
WHERE Snapshot_day between convert(date,getdate()-7) and convert(date,getdate()-1)
GROUP BY ProductBusinessID)


, Supplier AS (
    
    SELECT vd.No_ as [DivisionBusinessID],
      vd.Name as [DivisionName],
	  v.Name as [SupplierName],
	  v.No_ as [SupplierBusinessID]
      FROM [NBIS_FLA_STG].[dbo].FLA_VendorDivision vd
    LEFT JOIN NBIS_FLA_STG.dbo.FLA_Vendor v
    ON v.No_ = vd.[Vendor No_]


)

,
FCST7days as 
(Select ProductbusinessId, 
sum(isnull([Daily_Married_Forecast],0)) as [FCST 7days]
From [SNOP].[dbo].[SNOP_FCST_DAILY]
where [Calendar_Date] between convert(date,getdate()) and convert(date,getdate()+6) 
GROUP BY productbusinessid)

select  x.*, cast(r.[unit price] as float) as [last Price], AQ.Anlieferquote, LE.[Order Date], round(LT.Leadtime,1) as Leadtime, UL.Category_Uplift, UL.SKU_Uplift, UL.Brand_Uplift, US.[Units l7d], FC.[FCST 7days]
from (

SELECT 
      [Simple SKU]
      ,[Simple Status]
      ,[Simple Name]
                  ,SupplierName
                  ,DivisionName
      ,[Config SKU]
      ,[Config Visibility]    
      ,[Simple Date Release]
      ,CASE WHEN [Simple Date Release] <= GETDATE() THEN 1 ELSE 0 END AS [isReleased]
      ,[Simple Category]
      ,[Config Category]
      ,pp.ProductCategory1 as [ConfigCategory]
      ,[Simple Brand]
      ,[NAV Availability]
      ,[Simple Availability]
                  ,isnull(i.Quantity,0) - isnull(o.QtyOnOrder,0) as Quantity
                  ,ISNULL(c.OpenQty,0) as OpenQty
                  ,mand.Visits_split
                  ,mand.Visits_split_repl_OOS
                  ,bs.[BeautyScoreCluster]
                  ,wh.[Snapshot_date]
				  ,cast(ppp.[shopprice] as float) as [actual Price]
			
                

--from [OperationalFlaconi].[dbo].[ProductTableContent] p          
  FROM (SELECT
  
   distinct * 
                               from [OperationalFlaconi].[dbo].[ProductTableContent]) p
  full join (
                                                               SELECT 
                                                                                              ProductBusinessID
                                                                                              ,sum(Quantity) as Quantity
                                                                               FROM [OperationalFlaconi].[dbo].[WarehouseEntry] e
                                                                               group by ProductBusinessID
                                                                                 ) i
                                                               ON i.ProductBusinessID = p.[Simple SKU]
  full join (
                                                               SELECT 
                                                                                              p.ProductBusinessID
                                                                                 ,sum([QtyOnOrder]) as QtyOnOrder
                                                                 FROM [OperationalFlaconi].[dbo].[SalesOrderLine] s
                                                                               inner join [OperationalFlaconi].[dbo].[Product] p
                                                                               ON s.ProductID = p.ProductID   
                                                                               group by p.ProductBusinessID
                                                                               ) o
                                                               ON o.ProductBusinessID = p.[Simple SKU]
  left outer join (
                                                               SELECT [ProductBusinessID], sum([OpenQty]) [OpenQty]
                                                                 FROM [OperationalFlaconi].[dbo].[PurchaseLine]
                                                                 where [OpenQty] <> 0
                                                                 group by [ProductBusinessID]
                                                                 ) c
                                                               ON c.ProductBusinessID = p.[Simple SKU]
                                                               
left join (
              select 
                ProductBusinessID
                ,ProductCategory1
                                                               ,pro.SupplierBusinessID
                                                               ,sup.SupplierName
                                                               ,pro.DivisionBusinessID
                                                               ,sup.DivisionName
               from [OperationalFlaconi].[dbo].[Product] pro
                                                  left join Supplier sup
                                                  on  pro.DivisionBusinessID=sup.DivisionBusinessID) pp
           on pp.ProductBusinessID=p.[Simple SKU]

           
 left join (
                                               select 
                                               ProductBusinessID
                                               ,convert(decimal(18,2),SUM(Visits_split_repl_OOS)) as Visits_split_repl_OOS
                                               ,convert(decimal(18,2),SUM(Visits_split)) as Visits_split
                                               from OperationalFlaconi.dbo.Management_Report_Daily 
                                               where Snapshot_day=CONVERT(date,GETDATE()-1)
                                               group by ProductBusinessID) mand
on mand.ProductBusinessID=p.[Simple SKU] 

LEFT JOIN OperationalFlaconi.[otti].[BeautyScore] bs
                ON p.[NAV SKU] = bs.ProductBusinessID

left join OperationalFlaconi.dbo.Product ppp
				on ppp.ProductBusinessID = bs.ProductBusinessID





			  



INNER JOIN (Select ProductbusinessID ,min(Snapshot_date) as Snapshot_date FROM OperationalFlaconi.[dbo].[Warehouse_History]
GROUP BY ProductbusinessId) wh
ON p.[NAV SKU] = wh.ProductBusinessID



where ([NAV Availability] = 'Basis'
or 
[NAV Availability]= 'Limitiert')





) x

left join Anlieferquote AQ 
on [Simple SKU] = No_

left join lastEBE LE
on LE.productbusinessid = [Simple SKU]

left join Lieferzeit LT
on LT.productbusinessid = [Simple SKU]

left join Uplifts UL
on  UL.productbusinessid = [Simple SKU]

left join UnitsL7days US
on US.productbusinessid = [Simple SKU]

left join FCST7days FC
on FC.productbusinessid = [Simple SKU]

left join Unitprice R
on r.[item no_] = [Simple SKU]

where [Simple SKU] is not null
and [Simple Status] = 'activated'