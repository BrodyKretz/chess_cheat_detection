-- Can SQL catch chess cheaters? Flags Lichess players whose results are too good for their rating.
-- Run from this folder: duckdb lichess.db -f pipeline.sql

-- 1. Read the file as lines of text and keep the tag lines, the ones that start with "[".
CREATE OR REPLACE TABLE lines AS
SELECT line, ROW_NUMBER() OVER () AS line_number
FROM read_csv('lichess_db_standard_rated_2015-01.pgn.zst', header = false, delim = '', quote = '', columns = {'line': 'VARCHAR'})
WHERE line LIKE '[%';

-- 2. Split each tag line into a game id, a tag name and a value.
CREATE OR REPLACE TABLE tags AS
SELECT SUM(CASE WHEN line LIKE '[Event %' THEN 1 ELSE 0 END) OVER (ORDER BY line_number) AS game_id,
regexp_extract(line, '^\[(\w+) ', 1) AS tag,
regexp_extract(line, '"(.*)"', 1) AS value
FROM lines;

-- 3. One row per game.
CREATE OR REPLACE TABLE games AS
SELECT game_id,
MAX(CASE WHEN tag = 'White' THEN value END) AS white,
MAX(CASE WHEN tag = 'Black' THEN value END) AS black,
TRY_CAST(MAX(CASE WHEN tag = 'WhiteElo' THEN value END) AS INTEGER) AS white_elo,
TRY_CAST(MAX(CASE WHEN tag = 'BlackElo' THEN value END) AS INTEGER) AS black_elo,
TRY_CAST(MAX(CASE WHEN tag = 'WhiteRatingDiff' THEN value END) AS INTEGER) AS white_change,
TRY_CAST(MAX(CASE WHEN tag = 'BlackRatingDiff' THEN value END) AS INTEGER) AS black_change,
MAX(CASE WHEN tag = 'Result' THEN value END) AS result,
MAX(CASE WHEN tag = 'Termination' THEN value END) AS termination
FROM tags
GROUP BY game_id;

-- 4. One row per player per game: their rating, the opponent's rating, the points they scored and how their rating moved.
CREATE OR REPLACE VIEW player_games AS
SELECT game_id, white AS player, white_elo AS elo, black_elo AS opp_elo, white_change AS rating_change, termination,
CASE result WHEN '1-0' THEN 1.0 WHEN '0-1' THEN 0.0 ELSE 0.5 END AS score
FROM games
WHERE result IN ('1-0', '0-1', '1/2-1/2') AND termination <> 'Abandoned'

UNION ALL

SELECT game_id, black, black_elo, white_elo, black_change, termination,
CASE result WHEN '0-1' THEN 1.0 WHEN '1-0' THEN 0.0 ELSE 0.5 END
FROM games
WHERE result IN ('1-0', '0-1', '1/2-1/2') AND termination <> 'Abandoned';

-- 5. One row per player with 50 or more games: the points they scored, the points the Elo formula expected, and the gap between the two.
CREATE OR REPLACE TABLE profile AS
SELECT player,
COUNT(*) AS games,
ROUND(AVG(elo)) AS avg_elo,
ROUND(AVG(score), 3) AS actual,
ROUND(AVG(1 / (1 + POWER(10, (opp_elo - elo) / 400.0))), 3) AS expected,
ROUND(AVG(score) - AVG(1 / (1 + POWER(10, (opp_elo - elo) / 400.0))), 3) AS edge,
SUM(rating_change) AS rating_gain,
SUM(CASE WHEN termination = 'Rules infraction' AND score = 0 THEN 1 ELSE 0 END) AS infraction_losses
FROM player_games
WHERE elo IS NOT NULL AND opp_elo IS NOT NULL
GROUP BY player
HAVING COUNT(*) >= 50;

-- 6. Suspects score at least 0.15 points per game more than their rating predicts. A random 300 of everyone else is the control group.
CREATE OR REPLACE TABLE suspects AS
SELECT *
FROM profile
WHERE edge >= 0.15;

CREATE OR REPLACE TABLE control AS
SELECT *
FROM profile
WHERE edge < 0.15
ORDER BY random()
LIMIT 300;

-- Q1. How many games were read.
SELECT COUNT(*) AS total_games
FROM games;

-- Q2. The funnel: players with 50 or more games, suspects, and players who lost a game to a rules infraction.
SELECT COUNT(*) AS players,
SUM(CASE WHEN edge >= 0.15 THEN 1 ELSE 0 END) AS suspects,
SUM(CASE WHEN infraction_losses > 0 THEN 1 ELSE 0 END) AS infraction_losers
FROM profile;

-- Q3. The ten most suspicious players.
SELECT *
FROM suspects
ORDER BY edge DESC
LIMIT 10;

-- 7. Write the suspects and the control group for check_bans.py.
COPY (SELECT * FROM suspects ORDER BY edge DESC) TO 'suspects.csv' (HEADER);
COPY (SELECT * FROM control) TO 'control.csv' (HEADER);
