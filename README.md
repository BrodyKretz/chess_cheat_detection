# Can SQL Catch Chess Cheaters?

Lichess publishes every rated game played on the site. A player's rating predicts how many points they should score against each opponent, so a player who keeps scoring far above that prediction is either improving fast or getting help. This project uses one month of games (January 2015, about 1.5 million games) to flag the players whose results beat their rating the most, then asks the Lichess API which of them were later marked for cheating.

## How it works

`pipeline.sql` runs in DuckDB with no other tools:

1. Read the compressed game file as text and keep the header tags.
2. Split the tags into one row per game: both players, both ratings, both rating changes, the result and how the game ended.
3. Turn each game into two rows, one per player, with the points they scored (1, 0.5 or 0).
4. For every player with 50 or more games, compare the points they scored with the points the Elo formula expected given their opponents' ratings. The gap is their `edge`.
5. Anyone with an edge of 0.15 or more is a suspect. A random 300 of the rest are the control group.

`check_bans.py` then sends both lists to the Lichess API and counts how many accounts carry a terms of service violation, which is how Lichess marks cheaters.

## Results

![Funnel and top suspects](images/suspects.png)

![Ban check](images/check_bans.png)

## Run it (Mac)

```
brew install duckdb
curl -L -O https://database.lichess.org/standard/lichess_db_standard_rated_2015-01.pgn.zst
duckdb lichess.db -f pipeline.sql
python3 check_bans.py suspects.csv control.csv
```

The download is about 290 MB and is gitignored, along with the database and the CSV files. The data is CC0 from Lichess.

## What this can't do

The games file has no move times and engine evaluations on only a few games, so this only sees results, not moves. New accounts with provisional ratings gain rating fast and can look like suspects. And a terms of service mark can come years later for reasons other than cheating, so the ban check is a rough answer, not a verdict. The suspect list stays on your machine.
