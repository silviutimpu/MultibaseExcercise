[StagingDefinition = [Kind = "FastCopy"]]
section Section1;
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "incidents_raw_DataDestination", IsNewTarget = true], Settings = [Kind = "Manual", AllowCreation = true, ColumnSettings = [Mappings = {[SourceColumnName = "SourceID", DestinationColumnName = "SourceID"], [SourceColumnName = "Plant", DestinationColumnName = "Plant"], [SourceColumnName = "Month", DestinationColumnName = "Month"], [SourceColumnName = "SourceColumn", DestinationColumnName = "SourceColumn"], [SourceColumnName = "Value", DestinationColumnName = "Value"]}], DynamicSchema = false, UpdateMethod = [Kind = "Append"], TypeSettings = [Kind = "Table"]]]}]
shared incidents_raw = let
  Source        = Lakehouse.Contents(null),
  Workspace     = Source{[workspaceId = "b457e757-c2bf-4d03-bd9e-a8398292560c"]}[Data],
  LakehouseData = Workspace{[lakehouseId = "c1f5c887-d1cd-449e-b587-fd9cd21e2f57"]}[Data],

  // path-ul vine din registru; coborâm folder cu folder
  PathParts   = Text.Split(FilePath, "/"),
  FilesRoot   = LakehouseData{[Id = PathParts{0}, ItemKind = "Folder"]}[Data],
  FolderNames = List.Range(PathParts, 1, List.Count(PathParts) - 2),
  Folder      = List.Accumulate(FolderNames, FilesRoot, (acc, name) => acc{[Name = name]}[Content]),
  FileBinary  = Folder{[Name = List.Last(PathParts)]}[Content],

  Workbook = Excel.Workbook(FileBinary, null, true),
  Sheet    = Workbook{[Item = SheetName, Kind = "Sheet"]}[Data],
  Headers  = Table.PromoteHeaders(Sheet, [PromoteAllScalars = true]),

  // NUMAI cheile se tipizează aici; coloanele de măsuri nu se numesc nicăieri
  Typed = Table.TransformColumnTypes(Headers, {{"Plant", type text}, {"Month", type date}}),

  KeyList   = List.Transform(Text.Split(KeyColumns, ","), Text.Trim),
  Unpivoted = Table.UnpivotOtherColumns(Typed, KeyList, "SourceColumn", "Value"),

  Trimmed = Table.TransformColumns(Unpivoted, {
      {"SourceColumn", Text.Trim, type text},
      {"Plant",        Text.Trim, type text}
  }),

  WithSourceId = Table.AddColumn(Trimmed, "SourceID", each SourceId, Int64.Type),
  Reordered    = Table.ReorderColumns(WithSourceId, {"SourceID", "Plant", "Month", "SourceColumn", "Value"}),
  Final        = Table.TransformColumnTypes(Reordered, {{"Value", Int64.Type}})
in
  Final;
shared SourceId = 1 meta [IsParameterQuery = true, IsParameterQueryRequired = false, Type = type number, DefaultValue = null];
shared FilePath = "Files/landing/MultiBase_exercise_202608.xlsx" meta [IsParameterQuery = true, IsParameterQueryRequired = false, Type = type text, DefaultValue = ""];
shared SheetName = "Sheet1" meta [IsParameterQuery = true, IsParameterQueryRequired = false, Type = type text, DefaultValue = ""];
shared KeyColumns = "Plant,Month" meta [IsParameterQuery = true, IsParameterQueryRequired = false, Type = type text, DefaultValue = ""];
shared incidents_raw_DataDestination = let
  Pattern = Fabric.Warehouse([CreateNavigationProperties = false, HierarchicalNavigation = true]),
  Navigation_1 = Pattern{[workspaceId = "b457e757-c2bf-4d03-bd9e-a8398292560c"]}[Data],
  Navigation_2 = Navigation_1{[warehouseId = "4b5ebacf-89f3-4b82-9312-d7bbe3775b03"]}[Data],
  Navigation_3 = Navigation_2{[Schema = "bronze"]}[Data],
  TableNavigation = Navigation_3{[Name = "incidents_raw"]}?[Data]?
in
  TableNavigation;
