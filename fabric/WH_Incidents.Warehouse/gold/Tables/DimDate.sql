CREATE TABLE [gold].[DimDate] (

	[DateKey] int NOT NULL, 
	[Date] date NOT NULL, 
	[Year] int NOT NULL, 
	[MonthNumber] int NOT NULL, 
	[MonthShort] varchar(3) NOT NULL, 
	[Period] varchar(30) NOT NULL
);