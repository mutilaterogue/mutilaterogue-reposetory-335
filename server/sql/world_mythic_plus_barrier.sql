-- Mythic+ countdown walls (server/mythic_plus.cpp): spawned at the start of a keystone run, removed when the timer starts.
-- One row per wall; entry = your wall gameobject (700011 Wall Flat, 700012 Wall dome).
-- Position: stand where the wall goes in the mythic instance and use .gps.
CREATE TABLE IF NOT EXISTS `mythic_plus_barrier` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `map_id` INT UNSIGNED NOT NULL,
  `entry` INT UNSIGNED NOT NULL,
  `x` FLOAT NOT NULL,
  `y` FLOAT NOT NULL,
  `z` FLOAT NOT NULL,
  `o` FLOAT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `map_id` (`map_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- example (Utgarde Keep, dome at the entrance):
-- INSERT INTO `mythic_plus_barrier` (`map_id`, `entry`, `x`, `y`, `z`, `o`) VALUES (574, 700012, X, Y, Z, O);
