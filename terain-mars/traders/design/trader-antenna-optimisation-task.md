The script in terain-mars\traders\trader-antenna.lua is a Stationeers game script to direct a satelit dish to the signal.
It uses search algorithm to define the best position. Starting from some position it makes measurement with some angle step around the initial point. If the some point is better then current, it select this as a new best point and new better directrion.
It excludes oposit directions.
Also it rfeduce the step.
But if the signal we can retrieve we have an angle between signal and current direction.
It has sense to modify algorithm to use this angle as a step value for the better direction.
Check this approach or porpose better.
What we have to do to change the code to support this approach.
Tak in account that current optisation will break new approach.