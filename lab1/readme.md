## Lab1

### Building 

Compile mpi program: `mpicc -o pi pi.c`

`mpiexec -machinefile ./allnodes -np 2 ./pi 10`
`mpiexec -machinefile ../allnodes -np 1 ./pi 10`

### Zadanie domowe
Celem zadania jest zmierzenie wartości opóźnienia i charakterystyki przepustowości połączeń w klastrze.

- Należy przetestować dwa różne typy komunikacji P2P w MPI.
- Należy dokonać pomiarów (patrz ćw. 2):
    - przepustowości [Mbit/s] od długości komunikatów [B]: wykres,
    - opóźnienia [ms] przesyłania krótkiego komunikatu: wartość (opóźnienie definiujemy tutaj jako szczególny przypadek pomiaru przepustowości dla bardzo małego komunikatu (1B)).
- Implementacja w C lub Python.
- Sugestia: Do rysowania wykresów można użyć Gnuplot, pyplot, R/ggplot2.
- Zwrócić uwagę czy podczas testu maszyna jest obciążona - ktoś inny może puszczać w tym samym czasie testy, co zaburza wyniki. 
- Proszę przeprowadzić testy w następujących konfiguracjach:
    - Komunikacja na 1 nodzie - należy wziąć dwa procesory z jednej maszyny, spośród [vnode-01, ..., vnode-04].
    - Komunikacja między 2 nodami - należy wziąć po jednym procesorze z dwóch maszyn, spośród [vnode-05, ..., vnode-12].
- Wynikiem zadania jest pierwsza część sprawozdania - do wgrania na platformę razem z drugą częścią (bardzo niedaleka przyszłość).
    - Elementy konieczne do sprawozdania:
    - Kod programów.
    - Dane pomiarowe, komentarz odnośnie ich pozyskania.
    - Wykresy na podstawie wyliczeń z danych pomiarowych - tytuł, opisane osie, jednostki, serie (jeżeli występują). Niezależnie od tego, czy wygenerowane są osobne wykresy czy serie na jednym wykresie, powinno być jasno widoczne, z jakiej konfiguracji uruchomienia pochodzą dane (tytuł wykresu albo opis serii).
    - Opisy i wnioski do wykresów.
