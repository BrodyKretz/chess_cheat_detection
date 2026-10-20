-- Finds the players whose results beat their rating. Needs the tables from build.sql.
-- Run from this folder: duckdb lichess.db -f analysis.sql

-- 1. One row per player with 50 or more games: the points they scored, the points the Elo formula expected, and the gap between the two.
CREATE OR REPLACE TABLE profile AS  -- builds or rebuilds one summary row per player
SELECT player,
COUNT(*) AS games,
  
ROUND(AVG(elo)) AS avg_elo,
ROUND(AVG(score), 3) AS actual,
ROUND(AVG(1 / (1 + POWER(10, (opp_elo - elo) / 400.0))), 3) AS expected,
ROUND(AVG(score) - AVG(1 / (1 + POWER(10, (opp_elo - elo) / 400.0))), 3) AS edge,
SUM(rating_change) AS rating_gain,

COUNT(CASE WHEN termination = 'Rules infraction' AND score = 0 THEN 1 END) AS infraction_losses  -- how many games this player lost to a rules infraction
FROM player_games
WHERE elo IS NOT NULL AND opp_elo IS NOT NULL  -- skips games missing either player's rating, since the Elo math needs both
GROUP BY player
HAVING COUNT(*) >= 50;

-- 2. Suspects score at least 0.15 points per game more than their rating predicts. A random 300 of everyone else is the control group.
CREATE OR REPLACE TABLE suspects AS  -- builds or rebuilds the table of flagged players
SELECT *
FROM profile
WHERE edge >= 0.15;


CREATE OR REPLACE TABLE control AS
SELECT *
FROM profile
WHERE edge < 0.15
ORDER BY random()
LIMIT 300;

-- Q1. The funnel: players with 50 or more games, suspects, and players who lost a game to a rules infraction.
SELECT COUNT(*) AS players,
COUNT(CASE WHEN edge >= 0.15 THEN 1 END) AS suspects,
COUNT(CASE WHEN infraction_losses > 0 THEN 1 END) AS infraction_losers  -- how many players lost at least one game to a rules infraction
FROM profile;

-- Q2. The ten most suspicious players.
SELECT *
FROM suspects
ORDER BY edge DESC
LIMIT 10;

-- 3. Write the suspects and the control group for check_bans.py.
COPY (SELECT * FROM suspects ORDER BY edge DESC) TO 'suspects.csv' (HEADER);  -- saves every suspect to suspects.csv, biggest edge first, with column names on the first row
COPY (SELECT * FROM control) TO 'control.csv' (HEADER);  -- saves the 300 random control players to control.csv, with column names on the first row
