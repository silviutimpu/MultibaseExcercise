CREATE TABLE [meta].[ColumnMapping] (

	[MappingId] int NOT NULL, 
	[SourceId] int NOT NULL, 
	[SourceColumn] varchar(200) NOT NULL, 
	[Classification] varchar(50) NOT NULL, 
	[CodeGroup] varchar(50) NOT NULL, 
	[IsActive] bit NOT NULL
);