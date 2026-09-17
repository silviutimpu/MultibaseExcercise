CREATE TABLE [meta].[SourceRegistry] (

	[SourceId] int NOT NULL, 
	[SourceName] varchar(100) NOT NULL, 
	[FilePath] varchar(500) NOT NULL, 
	[SheetName] varchar(100) NOT NULL, 
	[IsActive] bit NOT NULL
);