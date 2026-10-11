-- Turns the Lichess text file into tables inside lichess.db.
-- Run from this folder: duckdb lichess.db -f build.sql

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
CREATE OR REPLACE TABLE player_games AS
SELECT game_id, white AS player, white_elo AS elo, black_elo AS opp_elo, white_change AS rating_change, termination,
CASE result WHEN '1-0' THEN 1.0 WHEN '0-1' THEN 0.0 ELSE 0.5 END AS score
FROM games
WHERE result IN ('1-0', '0-1', '1/2-1/2') AND termination <> 'Abandoned'

UNION ALL

SELECT game_id, black, black_elo, white_elo, black_change, termination,
CASE result WHEN '0-1' THEN 1.0 WHEN '1-0' THEN 0.0 ELSE 0.5 END
FROM games
WHERE result IN ('1-0', '0-1', '1/2-1/2') AND termination <> 'Abandoned';

SELECT COUNT(*) AS games_loaded
FROM games;
