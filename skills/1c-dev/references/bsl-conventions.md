# BSL and dump conventions

Traps that hold for any configuration edited through this skill. Each one loads, passes
`/CheckConfig` (or both) and only fails later — at run time, on the next dump, or on the
commit — so none of them is caught by the round-trip itself. They were met on a large,
heavily reworked configuration on platform 8.3.x; where a rule rests on one platform build,
it says so.

Read your own code against this list before `load-from-xml`: the designer does not compile
BSL on load, and a typo in a form module surfaces only when someone opens the form.

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
  one-line wrapper in `HTTPServices/<Имя>/Ext/Module.bsl` and put the service module in the
  load list.
- **`ПередЗаписью` of a record set also covers record-manager writes** — `ЭтотОбъект` behaves
  as a one-record set. A rule in the record-set module covers both ways of writing.
- **Date subtraction gives seconds**, and there is no global `РазностьДат`: a day count is
  `Цел((НачалоДня(b) - НачалоДня(a)) / 86400)`.
- Mark every parameter of an `Экспорт` method `Знач`; test optional inputs with
  `НЕ ЗначениеЗаполнено(X)` rather than `X = Неопределено`.

## Query text

Query text is not compiled on load or by `/CheckConfig`; every mistake below appears on
execution only.

- **Quotes double inside a BSL string.** The query's empty-string literal `""` is written
  `""""` inside a BSL string; `НЕ Поле = ""` there leaves an unterminated literal.
- **An alias must not be a query keyword** — `ИСТИНА КАК Есть` fails (`ЕСТЬ NULL`); so do
  `Выбор`, `Когда`, `Все`, `Различные`, `Первые`, `Подобно`, `Между`, `В`, `Итоги`.
- **An unlimited-length string cannot be compared**: `Поле <> ""` fails with «Нельзя
  сравнивать поля неограниченной длины»; write `НЕ Поле ПОДОБНО ""`.
- Unwrap a `СписокЗначений` to an array before `УстановитьПараметр`.

## Forms built in code

- **Set an element property only where the element's kind has it.** A property missing on
  that kind of field (`АвтоОтметкаНезаполненного` on a check box) throws. If the element is
  built inside a loop wrapped in one `Попытка` — the usual shape of code that builds a form
  from metadata — the exception silently drops every later element of the loop, and the form
  fails afterwards in unrelated code that looks for one of them. Put such a property under
  its own `Попытка`, or check the field's `Вид` first.
- **The dump omits default property values, so absence is information.** If a form property
  "does not work", grep the dump for its element: when only one value is ever written, the
  other is the default and has to be set explicitly.

## Files of the dump

- **BSL and XML are UTF-8 with BOM.** Stripping the BOM corrupts the file for the designer.
- **A file created from scratch comes out LF and BOM-less** — the designer accepts it, and the
  next dump rewrites the whole file, burying the real change in a full-file diff. Add the BOM
  and CRLF as a step of its own before loading.
- **Some dumped files mix CRLF with lone LF** (inside multi-line text in XML) and editors
  silently normalise them. Compare the CRLF and lone-LF counts with the committed file after
  an edit; the safe default for large XML is a byte-level replacement.
- **Attribute templates do not transfer between object kinds.** A catalog attribute carries
  `<Use>ForItem</Use>`, which a document has no such property for; copied into a document, it
  loads and the next dump drops the element — a diff hunk nobody wrote. Copy from the same
  kind of object.
- **A hand-written form or DCS file that the designer rejects is reported by bare file name**
  (`Form.xml`, `Template.xml`). Copy element syntax from a real dumped file. In a DCS schema, a
  QName in element *text* (`web:Black`, `style:…`, `d4p1:CatalogRef.…`) needs its prefix
  declared on that element or an ancestor; merged cells have no colspan — an empty cell
  carries `ОбъединятьПоГоризонтали` / `ОбъединятьПоВертикали`.

## Designer and repository

- **Changing an object's internal id makes it a new object** for the load. A child goes
  through with its parent listed; a top-level object needs `Configuration.xml` and the root
  lock. Grep the whole dump for the id first: forms can hold degraded references
  (`1/0:<uuid ТЧ>/0:<uuid реквизита>`).
- **Role rights are bound to object ids**, down to attributes: changing an id modifies every
  role holding rights on it, and the commit refuses until those roles are locked too.
- **Deleting a tabular section does not clean the forms that used it** — their items survive
  with `DataPath` degraded to raw GUID references and have to be removed by hand.
- **Lock the object a file is, plus every owner above it** — a form is locked under its full
  name (`Document.X.Form.Y`), a nested subsystem with all its parents. The designer names only
  the first missing lock, so lock the whole chain up front.
- **Launch `1cv8.exe` and wait for it** (`Start-Process -Wait -PassThru` in PowerShell, never
  `&`): the call operator returns at once, the designer detaches and keeps the infobase, and
  every later call fails with «с этой информационной базой уже работает конфигуратор».
- **`update-from-repo` can leave the tree half-updated**: when `/UpdateDBCfg` fails, the dump
  never runs and `git status` stays clean. Recover with `sync-xml`, not another update.
- **Sessions on one project share `.1c-work/`** — one lock ledger, one working tree. A second
  session's `commit-to-repo` commits and unlocks your objects too. Never `git stash` or check
  out the whole tree while `xmlDir` holds edits or a load runs: the designer reads the files
  and writes `ConfigDumpInfo.xml` during the load.
