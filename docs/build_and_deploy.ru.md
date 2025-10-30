## Структура проекта Blueprint

- `contracts` — исходный код всех смарт-контрактов проекта и их зависимости.
- `wrappers` — обёртки (классы, реализующие `Contract` из ton-core) для контрактов, включая примитивы для [де]сериализации и функции компиляции.
- `tests` — тесты для контрактов.
- `scripts` — скрипты, используемые в проекте, в основном для деплоя.

## Запуск контракта

### Добавить новый контракт

```bash
npx blueprint create ContractName
# или
yarn create ton ContractName
```
При создании выберите `An empty contract (TACT)`.

### Активировать актуальную версию компилятора

На момент написания данной инструкции используется версия 1.6.7. 
```bash
npx @tact-lang/compiler@1.6.7
# или
yarn add @tact-lang/compiler@1.6.7
```


### Сборка

```bash
npx blueprint build
# или
yarn blueprint build
```

### Развертывание или запуск скрипта

```bash
npx blueprint run
# или
yarn blueprint run
```

---
