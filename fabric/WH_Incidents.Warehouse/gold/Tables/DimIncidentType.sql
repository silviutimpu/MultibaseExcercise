CREATE TABLE [gold].[DimIncidentType] (

	[IncidentTypeKey] bigint NOT NULL, 
	[Classification] varchar(50) NOT NULL, 
	[CodeGroup] varchar(50) NOT NULL, 
	[IncidentTypeName] varchar(100) NOT NULL, 
	[SortOrder] bigint NOT NULL
);