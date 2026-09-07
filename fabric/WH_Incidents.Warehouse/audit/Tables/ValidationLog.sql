CREATE TABLE [audit].[ValidationLog] (

	[RunId] varchar(50) NOT NULL, 
	[RunTimestamp] datetime2(0) NOT NULL, 
	[SourceId] int NOT NULL, 
	[RuleId] int NOT NULL, 
	[RuleName] varchar(200) NOT NULL, 
	[Severity] varchar(20) NOT NULL, 
	[Passed] bit NOT NULL, 
	[Details] varchar(4000) NULL
);