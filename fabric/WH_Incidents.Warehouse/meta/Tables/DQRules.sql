CREATE TABLE [meta].[DQRules] (

	[RuleId] int NOT NULL, 
	[SourceId] int NULL, 
	[RuleName] varchar(200) NOT NULL, 
	[RuleType] varchar(50) NOT NULL, 
	[TargetColumn] varchar(200) NULL, 
	[RuleParameters] varchar(1000) NOT NULL, 
	[Severity] varchar(20) NOT NULL, 
	[IsActive] bit NOT NULL
);