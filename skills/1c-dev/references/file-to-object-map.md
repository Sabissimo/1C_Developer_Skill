# File → Metadata Object Mapping

How XML dump paths (relative to the XML dir) map to repository-lockable object names.
Implemented in `scripts/ps/Mapping.ps1` and `scripts/sh/mapping.sh` — keep all three in
sync.

## Rules

1. Normalize separators to `/`; strip a leading `./`.
2. `ConfigDumpInfo.xml` → **no object** (never locked, never edited by hand).
3. `Configuration.xml`, anything under `Configuration/`, and anything under the
   top-level `Ext/` → the **root** object (`<Configuration/>` element in objects.xml).
   Locking the root is required for configuration-level properties (subsystem
   composition, defaults, etc.) and for what the dump keeps in `<xmlDir>/Ext`: the
   configuration's own modules (`SessionModule.bsl`, `ManagedApplicationModule.bsl`,
   `OrdinaryApplicationModule.bsl`, `ExternalConnectionModule.bsl`), command interface,
   home page. Only the *top-level* `Ext/` is the root's — an object's own
   `<Dir>/<Obj>/Ext/…` falls under rule 6.
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
| `Ext/SessionModule.bsl` | root `Configuration` |
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

## File → module id (for `check-config`)

A different mapping with a different target: the name the designer prints in a check
finding, `{Документ.Заказ.МодульОбъекта(3,11)}: …`. Implemented in
`scripts/ps/Checking.ps1` and `scripts/sh/checking.sh`; the shared case table is
`scripts/tests/module-id-cases.txt`.

The id follows the configuration's **script variant**, so each file yields two ids — the
Russian and the English spelling — and a finding matches on either.

| Path | Module id (Russian / English) |
|---|---|
| `<Dir>/<Имя>/Ext/ObjectModule.bsl` | `Класс.Имя.МодульОбъекта` / `Class.Имя.ObjectModule` |
| `<Dir>/<Имя>/Ext/ManagerModule.bsl` | `….МодульМенеджера` / `….ManagerModule` |
| `<Dir>/<Имя>/Ext/RecordSetModule.bsl` | `….МодульНабораЗаписей` / `….RecordSetModule` |
| `<Dir>/<Имя>/Ext/ValueManagerModule.bsl` | `….МодульМенеджераЗначения` / `….ValueManagerModule` |
| `<Dir>/<Имя>/Ext/CommandModule.bsl` | `….МодульКоманды` / `….CommandModule` |
| `<Dir>/<Имя>/Ext/Module.bsl` | `….Модуль` / `….Module` |
| `<Dir>/<Имя>/Forms/<Форма>/Ext/Form/Module.bsl` or `…/Ext/Form.xml` | `Класс.Имя.Форма.<Форма>.Форма` / `Class.Имя.Form.<Форма>.Form` |
| `CommonForms/<Имя>/Ext/Form/Module.bsl` or `…/Ext/Form.xml` | `ОбщаяФорма.Имя.Форма` / `CommonForm.Имя.Form` |
| `<Dir>/<Имя>/Commands/<Команда>/Ext/CommandModule.bsl` | `Класс.Имя.Команда.<Команда>.МодульКоманды` / `Class.Имя.Command.<Команда>.CommandModule` |
| `Ext/ManagedApplicationModule.bsl`, `Ext/OrdinaryApplicationModule.bsl`, `Ext/SessionModule.bsl`, `Ext/ExternalConnectionModule.bsl` | `МодульУправляемогоПриложения`, `МодульОбычногоПриложения`, `МодульСеанса`, `МодульВнешнегоСоединения` / the file name |

`Класс` is the Russian class name (`Справочник`, `Документ`, `ОбщийМодуль`, … — table
`CLASS_RU_BY_DIR` / `class_ru_by_dir`). A form's `Ext/Form.xml` counts as its module
because that is the file `load-from-xml` lists for it.

Files that hold no module (object `.xml`, templates, predefined data) map to nothing. A
`.bsl` file that fits none of the rows is an **error** (exit 4), never a silent skip —
otherwise that module's findings would be filed under "elsewhere".

Verified live (8.3.19.1351, Russian script variant): `МодульОбъекта`, `МодульМенеджера`,
the form id and the root `МодульСеанса` (printed bare: `{МодульСеанса(2,2)}: …`). The
other rows and the English spellings follow the platform's naming
but have not been seen in a real check log yet; nested external-data-source tables and
recalculations have no row.
