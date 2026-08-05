# File → Metadata Object Mapping

How XML dump paths (relative to the XML dir) map to repository-lockable object names.
Implemented in `scripts/ps/Mapping.ps1` and `scripts/sh/mapping.sh` — keep all three in
sync.

## Rules

1. Normalize separators to `/`; strip a leading `./`.
2. `ConfigDumpInfo.xml` → **no object** (never locked, never edited by hand).
3. `Configuration.xml` or anything under `Configuration/` → the **root** object
   (`<Configuration/>` element in objects.xml). Locking the root is required for
   configuration-level properties (subsystem composition, defaults, etc.).
4. First path segment must be a known plural directory (table below) → class name.
   Second segment (with `.xml`/`.bsl`/`.mdo` stripped) → object name: `Class.Имя`.
5. **Forms and templates are separately lockable**:
   - `<Dir>/<Obj>/Forms/<Форма>[.xml|/…]` → `Class.Obj.Form.Форма`
   - `<Dir>/<Obj>/Templates/<Макет>[.xml|/…]` → `Class.Obj.Template.Макет`
   - Except `CommonForms/…` and `CommonTemplates/…`, which are already top-level
     (`CommonForm.Имя`, `CommonTemplate.Имя`).
6. Everything else under an object (`Ext/ObjectModule.bsl`, `Ext/ManagerModule.bsl`,
   attributes, commands, predefined items) → the object itself: `Class.Имя`.
7. Unknown top-level directory → error (exit 4). Lock manually via
   `--objects "Class.Имя"` and file an issue.

## Examples

| Path | Object |
|---|---|
| `Catalogs/Товары.xml` | `Catalog.Товары` |
| `Catalogs/Товары/Ext/ObjectModule.bsl` | `Catalog.Товары` |
| `Catalogs/Товары/Forms/ФормаЭлемента/Ext/Form/Module.bsl` | `Catalog.Товары.Form.ФормаЭлемента` |
| `Documents/Заказ/Templates/Печать.xml` | `Document.Заказ.Template.Печать` |
| `CommonModules/ОбщегоНазначения/Ext/Module.bsl` | `CommonModule.ОбщегоНазначения` |
| `CommonForms/Настройки/Ext/Form/Module.bsl` | `CommonForm.Настройки` |
| `Configuration.xml` | root `Configuration` |
| `ConfigDumpInfo.xml` | — (skipped) |

## Directory → class table

| Directory | Class |
|---|---|
| Languages | Language |
| Subsystems | Subsystem |
| StyleItems | StyleItem |
| Styles | Style |
| CommonPictures | CommonPicture |
| SessionParameters | SessionParameter |
| Roles | Role |
| CommonTemplates | CommonTemplate |
| FilterCriteria | FilterCriterion |
| CommonModules | CommonModule |
| CommonAttributes | CommonAttribute |
| ExchangePlans | ExchangePlan |
| XDTOPackages | XDTOPackage |
| WebServices | WebService |
| HTTPServices | HTTPService |
| WSReferences | WSReference |
| EventSubscriptions | EventSubscription |
| ScheduledJobs | ScheduledJob |
| SettingsStorages | SettingsStorage |
| FunctionalOptions | FunctionalOption |
| FunctionalOptionsParameters | FunctionalOptionsParameter |
| DefinedTypes | DefinedType |
| CommonCommands | CommonCommand |
| CommandGroups | CommandGroup |
| Constants | Constant |
| CommonForms | CommonForm |
| Catalogs | Catalog |
| Documents | Document |
| DocumentNumerators | DocumentNumerator |
| Sequences | Sequence |
| DocumentJournals | DocumentJournal |
| Enums | Enum |
| Reports | Report |
| DataProcessors | DataProcessor |
| ChartsOfCharacteristicTypes | ChartOfCharacteristicTypes |
| ChartsOfAccounts | ChartOfAccounts |
| ChartsOfCalculationTypes | ChartOfCalculationTypes |
| InformationRegisters | InformationRegister |
| AccumulationRegisters | AccumulationRegister |
| AccountingRegisters | AccountingRegister |
| CalculationRegisters | CalculationRegister |
| BusinessProcesses | BusinessProcess |
| Tasks | Task |
| ExternalDataSources | ExternalDataSource |
| IntegrationServices | IntegrationService |
| Bots | Bot |

Known v1 simplification: nested parts of `ExternalDataSources` (tables, cubes) and
`CalculationRegisters` recalculations map to their top-level object.
