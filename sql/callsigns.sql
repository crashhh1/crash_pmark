CREATE TABLE IF NOT EXISTS `callsigns` (
  `identifier` varchar(60) NOT NULL,
  `callsign` varchar(32) NOT NULL,
  PRIMARY KEY (`identifier`),
  UNIQUE KEY `callsign` (`callsign`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
