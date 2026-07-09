# Lab: Mule properties + Vault + Concourse

Lokalny sandbox do zobaczenia na żywo jak działa: `{{placeholder}}` w configu Mule
-> Concourse (resources / jobs / tasks) -> Vault (sekrety) -> podstawiona wartość.

Foldery:
- `mule-app/` - przykładowy "projekt Mule" z placeholderami w plikach configowych.
- `ci/pipeline.yml` - definicja pipeline'u Concourse (resource `git` + 2 joby: dev, prod).
- `ci/tasks/` - 3 taski: podstawienie placeholderów, "build" (mock), "deploy" (mock).
- `ci/vars/repo.yml` - tu wpisujesz URL swojego repo GitHub.
- `vault/`, `scripts/up.sh` - inicjalizacja Vault i start całego stacka.

## 0. Wymagania

- Docker Desktop uruchomiony (`docker info` ma działać bez błędu).
- Konto GitHub (na potrzeby resource `git` w Concourse).
- `fly` CLI (pobierzemy je z samego Concourse w kroku 3).

## 1. Odpal Vault + Postgres + Concourse

```bash
cd mule-vault-concourse-lab
./scripts/up.sh
```

Skrypt: startuje kontenery, włącza w Vault silnik KV v2 pod ścieżką `concourse`,
wgrywa przykładowe sekrety (`db_password`, `api_key` dla `dev` i `prod`),
i czeka aż Concourse odpowie na `:8080`.

Sprawdź:
- Vault UI: http://localhost:8200 (token: `root`) - w zakładce Secrets zobaczysz
  silnik `concourse/` i ścieżki `main/mule-app/dev/...`, `main/mule-app/prod/...`.
- Concourse UI: http://localhost:8080 (login: `test` / `test`).

## 2. Wypchnij `mule-app/` + `ci/` do repo na GitHubie

Concourse musi mieć skąd pobrać kod (resource typu `git`) - lokalna ścieżka na
dysku nie wystarczy, bo taski/resource'y działają w osobnych kontenerach.

```bash
# w folderze mule-vault-concourse-lab
git init
git add mule-app ci
git commit -m "mule-app + concourse pipeline"
git branch -M main
git remote add origin https://github.com/TWOJ_USER/mule-vault-demo.git
git push -u origin main
```

(Repo może być publiczne - nie ma tam żadnych sekretów, tylko placeholdery `{{...}}`.)

Zaktualizuj `ci/vars/repo.yml` -> wstaw prawdziwy URL swojego repo.

## 3. Zainstaluj `fly` CLI i zaloguj się do Concourse

Concourse UI (http://localhost:8080) ma w prawym dolnym rogu link do pobrania
`fly` dopasowanego do Twojego systemu. Albo z terminala (macOS):

```bash
curl -Lo fly "http://localhost:8080/api/v1/cli?arch=amd64&platform=darwin"
chmod +x fly
sudo mv fly /usr/local/bin/fly

fly -t lab login -c http://localhost:8080 -u test -p test -n main
```

## 4. Wgraj pipeline

```bash
fly -t lab set-pipeline -p mule-app -c ci/pipeline.yml -l ci/vars/repo.yml
fly -t lab unpause-pipeline -p mule-app
```

Odśwież http://localhost:8080 - zobaczysz pipeline `mule-app` z resource'em
`mule-repo` i dwoma jobami: `build-and-deploy-dev`, `build-and-deploy-prod`.

## 5. Odpal job i patrz jak działa

```bash
fly -t lab trigger-job -j mule-app/build-and-deploy-dev -w
```

Flaga `-w` = watch, zobaczysz logi na żywo w terminalu. W logach taska
`replace-placeholders` zobaczysz:

```
=== Plik przed podstawieniem ===
password: {{db_password}}
=== Plik po podstawieniu wartosci z Vault ===
password: SuperTajneHaslo-DEV
```

To jest dokładnie moment, w którym Concourse poszedł do Vault po wartość
`((mule-app/dev/db_password))` i wstrzyknął ją jako zmienną środowiskową
tylko na czas trwania taska - nigdzie nie jest zapisana na stałe w pipeline.yml.

Job `build-and-deploy-prod` ma `passed: [build-and-deploy-dev]`, więc
odblokuje się dopiero gdy dev przejdzie - to typowy wzorzec "promocji"
między środowiskami. Możesz go odpalić tak samo:

```bash
fly -t lab trigger-job -j mule-app/build-and-deploy-prod -w
```

## 6. Do poeksperymentowania

- Podmień wartość w Vault i odpal job ponownie - zobaczysz nową wartość
  bez zmiany jednej linijki w pipeline.yml:
  ```bash
  docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root vault \
    vault kv put concourse/main/mule-app/dev/db_password value=INNE-HASLO
  fly -t lab trigger-job -j mule-app/build-and-deploy-dev -w
  ```
- Wejdź "do środka" kontenera taska w trakcie/po jego działaniu:
  ```bash
  fly -t lab intercept -j mule-app/build-and-deploy-dev -s replace-placeholders
  ```
- Zobacz historię buildów: `fly -t lab builds`
- Zobaczy resource i wymuś sprawdzenie nowej wersji z GitHuba:
  `fly -t lab check-resource -r mule-app/mule-repo`
- Podejrzyj surowy pipeline: `fly -t lab get-pipeline -p mule-app`

## 7. Sprzątanie

```bash
./scripts/down.sh
```

Usuwa kontenery i wolumeny (dane w Vault/Concourse-DB przepadają - to sandbox,
nic tu nie jest trwałe ani produkcyjne).

## Gdzie tu wchodzi AWS Secrets Manager?

Celowo pominięty w tym sandboxie. To co widzisz tutaj to warstwa
**build/deploy-time** (Concourse pyta Vault o sekret, podstawia go w pliku
configu, pakuje i "wdraża"). AWS Secrets Manager wchodziłby dodatkowo,
gdyby to **sama uruchomiona aplikacja Mule w runtime** miała sama, przy
starcie, pytać o sekret (przez IAM, bez udziału Vault/Concourse) zamiast
dostawać go już wypieczonego w pliku configu podczas deployu. To osobny,
kolejny krok - śmiało odezwij się, jak zechcesz go dorzucić.
