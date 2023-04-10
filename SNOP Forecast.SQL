SELECT
			 fc.ProductBusinessID
			,ROUND(SUM(CASE WHEN Calendar_Date >= getdate() AND Calendar_Date < (getdate() + 7) THEN Daily_Married_Forecast ELSE 0 END),0) AS FCST_7days
			,ROUND(SUM(CASE WHEN Calendar_Date >= getdate() AND Calendar_Date < (getdate() + 30) THEN Daily_Married_Forecast ELSE 0 END),0) AS FCST_30days
			,ROUND(SUM(CASE WHEN Calendar_Date >= getdate() AND Calendar_Date < (getdate() + 45) THEN Daily_Married_Forecast ELSE 0 END),0) AS FCST_45days
			,ROUND(SUM(CASE WHEN Calendar_Date >= getdate() AND Calendar_Date < (getdate() + 56) THEN Daily_Married_Forecast ELSE 0 END),0) AS FCST_56days
			,cast([unitcost] as float) as [Unit Cost]
		FROM [SNOP].[dbo].[SNOP_FCST_DAILY] fc
		join operationalflaconi.dbo.product p
		on fc.productbusinessid = p.ProductBusinessID
		GROUP BY fc.ProductBusinessID, [UnitCost]