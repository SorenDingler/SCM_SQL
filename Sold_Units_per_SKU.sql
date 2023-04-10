SELECT productname, ProductBusinessID, 
sum(ordered_qty)as Sold_Units, 
sum(Invoiced_Sales_aD)as Revenue, 
sum(Invoiced_DB3_aD) as Profit, 
sum(Invoiced_DB3_aD)/sum(Invoiced_Sales_aD) as DB3_Marge  
FROM [operationalflaconi].dbo.Management_report_daily
WHERE [Snapshot_day] > '2017-01-01'
and Invoiced_Sales_aD > 0
and Invoiced_DB3_aD >0
--and productbusinessid ='40003070'
--and divisionbusinessid = 'pau001'
-- and productbusinessid = '20102382'
--and productname like 'Emporio Armani YOU%'
--and brand = 'Emporio Armani'
GROUP BY ProductBusinessID, ProductName
ORDER BY Verk�ufe desc