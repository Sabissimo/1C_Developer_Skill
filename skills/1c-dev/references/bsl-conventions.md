# BSL and dump conventions

Traps that hold for any configuration edited through this skill. Each one loads, passes
`/CheckConfig` (or both) and only fails later — at run time, on the next dump, or on the
commit — so none of them is caught by the round-trip itself. They were met on a large,
heavily reworked configuration on platform 8.3.x; where a rule rests on one platform build,
it says so.

Read your own code against this list before `load-from-xml`: the designer does not compile
BSL on load, and a typo in a form module surfaces only when someone opens the form. With no
compiler behind the load, check by eye at least:

- every `Если`/`Цикл`/`Попытка` is closed by its `КонецЕсли`/`КонецЦикла`/`КонецПопытки`;
- every procedure you call exists, and takes that many parameters;
- no reserved word is used as a name — of a variable, a parameter, or a query alias;
- every `""` inside a query text is doubled (Query text, below).

## BSL

- **Never name a variable after a common module.** A common module's name is a read-only
  property of the global context: `Сотрудники = Новый Массив` loads, passes `/CheckConfig`
  and dies at run time. Declaring the name as a *parameter* is legal; assigning to an
  undeclared local is not. `load-from-xml` refuses such a file (exit 5, `collisions`);
  domain nouns are the tempting names — `Сотрудники`, `Пользователи`, `ГрафикиРаботы`.
- **A form module has no `&НаКлиентеНаСервере`.** The client-and-server directive there is
  `&НаКлиентеНаСервереБезКонтекста` only; a procedure that needs the form takes it as a
  parameter. The wrong directive loads, and the form fails on opening with «Процедура или
  функция с указанным именем не определена».
- **An HTTP-service method handler is a function of the service's own module.** A
  `<Handler>` bound to a name that lives only in a common module fails at call time; keep a
  one-line wrapper in `HTTPServices/<Имя>/Ext/Module.bsl` that delegates to the common
  module. A new URL template needs its wrapper too, and the service module in the load list.
- **`ПередЗаписью` of a record set also covers record-manager writes.** Writing an
  information register through `СоздатьМенеджерЗаписи()` goes through the same handler as
  `СоздатьНаборЗаписей()`, with `ЭтотОбъект` behaving as a one-record set: `Для Каждого …
  Из ЭтотОбъект` iterates it and `Отбор` carries the record key. A rule in the record-set
  module therefore covers both ways of writing; repeating it at the `СоздатьМенеджерЗаписи`
  call sites is wasted work. Typical configurations rely on this — register modules loop
  over `ЭтотОбъект` in `ПередЗаписью(Отказ, Замещение)` while vendor code writes the same
  registers by manager.
- **Code that creates an object in place of its form gets no fill values.** A form for a
  new object receives the attributes' `FillValue` from the platform before
  `ПриСозданииНаСервере`; `СоздатьЭлемент()` / `СоздатьДокумент()` followed by a direct call
  of `ОбработкаЗаполнения` / `Заполнить` does not. Grep the object's `.xml` for `<FillValue`
  that is not `xsi:nil` and set those values yourself. Nor does a new document get a date
  before `ПередЗаписью`: set `Дата` before `Заполнить`, or a change-prohibition check rejects
  01.01.0001.
- **Date subtraction gives seconds**, and there is no global `РазностьДат`: a day count is
  `Цел((НачалоДня(b) - НачалоДня(a)) / 86400)`.
- Mark every parameter of an `Экспорт` method `Знач`; test optional inputs with
  `НЕ ЗначениеЗаполнено(X)` rather than `X = Неопределено`.

## Query text

Query text is not compiled on load or by `/CheckConfig`; every mistake below appears on
execution only.

- **Quotes double inside a BSL string.** The query's empty-string literal `""` is written
  `""""` inside a BSL string; `НЕ Поле = ""` there leaves `= "` with an unterminated
  literal. The same query pasted into a form's dynamic-list XML keeps `""` as is. Check
  every `""` on the `|` lines before loading.
- **An alias must not be a query keyword** — `ИСТИНА КАК Есть` fails (`ЕСТЬ NULL`); so do
  `Выбор`, `Когда`, `Все`, `Различные`, `Первые`, `Подобно`, `Между`, `В`, `Итоги`. Name
  aliases after what they mean (`ЕстьКонтрагент`).
- **A table alias must not match a field name of another table in the same query.** A field
  may be written without its table prefix, so in `Документ.ПеремещениеЗапасов КАК
  Перемещение ЛЕВОЕ СОЕДИНЕНИЕ РегистрСведений.<Регистр> КАК Р` — where the register has a
  dimension `Перемещение` — the text `Перемещение.СтруктурнаяЕдиницаПолучатель` reads both
  as the document's attribute and as a dereference of that dimension, and execution fails
  with `Неоднозначное поле`. Alias a table by its full name, or by anything that is not a
  column of a joined table.
- **An unlimited-length string cannot be compared**: `Поле <> ""` fails with «Нельзя
  сравнивать поля неограниченной длины»; write `НЕ Поле ПОДОБНО ""`.
- Unwrap a `СписокЗначений` to an array before `УстановитьПараметр`.

## Forms

- **Set an element property only where the element's kind has it.** A property missing on
  that kind of field (`АвтоОтметкаНезаполненного` on a check box) throws. If the element is
  built inside a loop wrapped in one `Попытка` — the usual shape of code that builds a form
  from metadata — the exception silently drops every later element of the loop, and the form
  fails afterwards in unrelated code that looks for one of them. Put such a property under
  its own `Попытка`, or check the field's `Вид` first.
- **Dropping text into a field: the target does the work, not your handlers.** The target
  must be a `ПолеТекстовогоДокумента` — a plain input field is not one — and must carry
  **no** drag handlers: the platform inserts at the drop point itself. All the source needs
  is a `НачалоПеретаскивания` handler that replaces `ПараметрыПеретаскивания.Значение` (an
  array of row ids by default) with the string to insert. Handlers on the target that set
  `СтандартнаяОбработка = Ложь` silence exactly the behaviour you want. `ПодсказкаВвода`
  belongs to input fields only, so the text-document field cannot carry one.

## Files of the dump

- **BSL and XML are UTF-8 with BOM.** Stripping the BOM corrupts the file for the designer.
- **A file created from scratch comes out LF and BOM-less** — the designer accepts it, and the
  next dump rewrites the whole file, burying the real change in a full-file diff. Add the BOM
  and CRLF as a step of its own before loading.
- **Git must not touch line endings.** A project under git needs `.gitattributes` with
  `* -text`, so that the tree matches the designer's output byte for byte. Do not "fix"
  line endings in a dumped file.
- **Some dumped files mix CRLF with lone LF** — inside multi-line `<v8:content>` elements,
  query texts and other multi-line text in XML — and editing tools silently normalise them:
  a whole-file rewrite turns every lone LF into CRLF and produces diff hunks far from the
  intended change. After each edit compare `b.count(b"\r\n")` and
  `b.count(b"\n") - b.count(b"\r\n")` with the same counts of `git show HEAD:<path>`. If they
  differ, rebuild the file from the committed bytes: re-apply the change as a byte-level
  `replace` on the original, or walk `difflib.SequenceMatcher` over both line lists and take
  `equal` runs from the original and `insert` runs from the edit. Doing insertions
  byte-level in the first place avoids the problem and is the better default for large XML.
- **The dump omits default property values, so absence is information.** `<MultipleChoice>`
  is only ever written as `true`, so its default is `false`: a form table without the
  element has multi-row selection off, and Ctrl-click does nothing until it is added. When a
  property "does not work", grep the dump for its element: if only one value is ever
  written, the other is the default and has to be set explicitly.
- **Attribute templates do not transfer between object kinds.** A catalog attribute carries
  `<Use>ForItem</Use>`, which a document has no such property for; copied into a document, it
  loads and the next dump drops the element — a diff hunk nobody wrote. Copy from the same
  kind of object.
- **A hand-written form or DCS file that the designer rejects is reported by bare file name**
  (`Form.xml`, `Template.xml`) in the designer log. Copy element syntax from a real dumped
  file rather than inventing it; for DCS see the next section.

## Hand-written DCS schemas

- **A QName in element *text* needs its prefix declared** on that element or an ancestor —
  `web:Black` for a border colour, `style:…`, `d4p1:CatalogRef.…`. An XML parser does not
  see the problem, the designer answers with the bare `Template.xml`. Write it the way dumps
  do: `<dcscor:value xmlns:web="http://v8.1c.ru/8.1/data/ui/colors/web" …>web:Black`.
- **Merged cells in an area template have no colspan.** The dump writes an empty
  `dcsat:tableCell` carrying `ОбъединятьПоГоризонтали` or `ОбъединятьПоВертикали`, which
  joins it to the cell before it or above it.
- **The rendered layout follows the cells, not the intent.** Templates with the same cell
  count share one column grid (the widths come from the cells that set them); a merged run
  whose text is left-aligned comes out cut to the text width; a box drawn as two merged rows
  loses the line between them. So give a title or footer a grid of its own (a template with
  fewer cells — shipped schemas mix 2-, 5- and 10-cell templates), make every bordered box a
  single cell with explicit widths, and merge only centred captions.
- **In УНФ-based configurations, choice parameters and links written on a DCS *parameter*
  do not reach its input field** in `ОбщаяФорма.ФормаОтчетаУНФ`: the form passes only
  `ДоступныеЗначения` for parameters, and `ОтчетыУНФ.СоздатьФильтрПолеВвода` takes a
  `СвязиПараметровВыбора` argument it never uses (the same in two independently reworked
  УНФ derivatives). Set them on the form element instead, from the report's
  `ОбновитьНастройкиНаФорме` hook, which the form calls when the report's settings have
  `ПрограммноеИзменениеФормыОтчета`. This works for **parameter** fields only — their sole
  handler is `ПриИзменении` and choice stays standard; a filter field gets
  `Подключаемый_ФильтрНачалоВыбора`, which opens the choice form itself and reads no links.
  Link with `НеИзменять`: a value the platform clears fires no `ПриИзменении`, so the DCS
  parameter would keep the old value.

## Designer and repository

- **Changing an object's internal id makes it a new object.** `load-from-xml` matches
  objects by internal id, so a file whose `uuid=` changed is new to it. A **child** — a
  tabular section, an attribute — goes through, because its parent is in the file list. A
  **top-level** object fails with `нельзя добавлять объекты метаданных без загрузки
  родительского объекта`; loading it means `Configuration.xml` and the root lock, i.e. the
  near-full reload (SKILL.md, Workflow 3). Before touching any id, grep the whole dump for
  it: forms can hold degraded references (`1/0:<uuid ТЧ>/0:<uuid реквизита>`) that the change
  breaks. Align only the depth something actually references — a characteristics
  description pointing at a tabular section needs that section's id, and, if its `ПолеВида`
  and `ПолеЗначения` are filled, the *attributes'* ids as well.
- **Role rights are bound to object ids, down to attributes.** In the dump a role names its
  objects (`<name>Catalog.Товары</name>`), but internally rights are stored per identifier —
  tabular sections and their attributes included. Changing an id therefore modifies every
  role holding rights on it, and `commit-to-repo` refuses with `Для выполнения операции
  необходимо поместить в хранилище объекты: Роль.<Имя> (объект не захвачен пользователем)`
  until those roles are locked too. Lock them up front: grep `Roles/*/Ext/Rights.xml` for
  the object's name.
- **Deleting a tabular section does not clean the forms that used it** — their items survive
  with `DataPath` degraded to raw GUID references and have to be removed by hand.
- **Lock the object a file is, plus every owner above it** — SKILL.md, Workflow 3, step 2.
- **Launch `1cv8.exe` and wait for it** (`Start-Process -Wait -PassThru` in PowerShell, never
  `&`): the call operator returns at once, the designer detaches and keeps the infobase, and
  every later call fails with «с этой информационной базой уже работает конфигуратор».
- **`update-from-repo` can leave the tree half-updated**: when `/UpdateDBCfg` fails, the dump
  never runs and `git status` stays clean. Recover with `sync-xml`, not another update —
  [troubleshooting.md](troubleshooting.md).
- **Sessions on one project share `.1c-work/`** — one lock ledger, one working tree; a second
  session's `commit-to-repo` commits and unlocks your objects too. SKILL.md, Parallel
  sessions on one project.
