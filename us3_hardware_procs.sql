--
-- us3_hardware_procs.sql
--
-- Script to set up the MySQL stored procedures for the US3 system
--   These are related to various tables pertaining to hardware
-- Run as root
--

DELIMITER $$

--
-- Rotor Calibration procedures
--

-- Returns the count of all calibration profiles associated with a given rotor
DROP FUNCTION IF EXISTS count_rotor_calibrations$$
CREATE FUNCTION count_rotor_calibrations ( p_personGUID CHAR(36),
                                           p_password   VARCHAR(80),
                                           p_rotorID    INT )
  RETURNS INT
  READS SQL DATA

BEGIN

  DECLARE count_profiles INT;
  DECLARE count_rotors      INT;

  CALL config();
  SET count_profiles = 0;

  SELECT     COUNT(*)
  INTO       count_rotors
  FROM       rotor
  WHERE      rotorID = p_rotorID;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    IF ( count_rotors < 1 ) THEN
      SET @US3_LAST_ERRNO = @NO_ROTOR;
      SET @US3_LAST_ERROR = CONCAT('MySQL: No rotor with ID ',
                                   p_rotorID,
                                   ' exists' );

    ELSE
      SELECT    COUNT(*)
      INTO      count_profiles
      FROM      rotorCalibration
      WHERE     rotorID = p_rotorID;

    END IF;

  END IF;

  RETURN( count_profiles );

END$$

-- Returns the count of all calibration profiles associated with a given
--  experiment
DROP FUNCTION IF EXISTS count_calibration_experiments$$
CREATE FUNCTION count_calibration_experiments ( p_personGUID CHAR(36),
                                                p_password   VARCHAR(80),
                                                p_experimentID INT )
  RETURNS INT
  READS SQL DATA

BEGIN

  DECLARE count_profiles    INT;
  DECLARE count_experiments INT;

  CALL config();
  SET count_profiles = -1;    -- 0 could be a legitimate count

  SELECT     COUNT(*)
  INTO       count_experiments
  FROM       experiment
  WHERE      experimentID = p_experimentID;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    IF ( count_experiments < 1 ) THEN
      SET @US3_LAST_ERRNO = @NO_EXPERIMENT;
      SET @US3_LAST_ERROR = CONCAT('MySQL: No experiment with ID ',
                                   p_experimentID,
                                   ' exists' );

    ELSE
      SELECT    COUNT(*)
      INTO      count_profiles
      FROM      rotorCalibration
      WHERE     calibrationExperimentID = p_experimentID;

    END IF;

  END IF;

  RETURN( count_profiles );

END$$

-- SELECTs names of all rotor calibration profiles associated with a rotor
DROP PROCEDURE IF EXISTS get_rotor_calibration_profiles$$
CREATE PROCEDURE get_rotor_calibration_profiles ( p_personGUID CHAR(36),
                                                  p_password   VARCHAR(80),
                                                  p_rotorID    INT )
  READS SQL DATA

BEGIN
  DECLARE count_profiles INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    SELECT    COUNT(*)
    INTO      count_profiles
    FROM      rotorCalibration
    WHERE     rotorID = p_rotorID;

    IF ( count_profiles = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';
 
      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT   rotorCalibrationID, dateUpdated, label
      FROM     rotorCalibration
      WHERE    rotorID = p_rotorID
      ORDER BY dateUpdated DESC;
 
    END IF;

  END IF;

END$$

-- Returns a more complete list of information about one rotor calibration profile
DROP PROCEDURE IF EXISTS get_rotor_calibration_info$$
CREATE PROCEDURE get_rotor_calibration_info ( p_personGUID CHAR(36),
                                              p_password   VARCHAR(80),
                                              p_calibrationID INT )
  READS SQL DATA

BEGIN
  DECLARE count_profiles INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_profiles
  FROM       rotorCalibration
  WHERE      rotorCalibrationID = p_calibrationID;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    IF ( count_profiles = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';

      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT   rotorCalibrationGUID, rotorCalibration.rotorID, rotorGUID,
               report, coeff1, coeff2, omega2_t, dateUpdated, 
               calibrationExperimentID, label 
      FROM     rotorCalibration, rotor
      WHERE    rotorCalibrationID = p_calibrationID
      AND      rotorCalibration.rotorID = rotor.rotorID;

    END IF;

  ELSE
    SELECT @US3_LAST_ERRNO AS status;

  END IF;

END$$

-- adds a new rotor calibration profile
-- the experimentID is the ID of the calibration experiment
-- experimentID = -1 is a special value that doesn't exist
DROP PROCEDURE IF EXISTS add_rotor_calibration$$
CREATE PROCEDURE add_rotor_calibration ( p_personGUID        CHAR(36),
                                         p_password          VARCHAR(80),
                                         p_rotorID           INT,
                                         p_calibrationGUID   CHAR(36),
                                         p_report            TEXT,
                                         p_coeff1            FLOAT,
                                         p_coeff2            FLOAT,
                                         p_omega2_t          FLOAT,
                                         p_experimentID      INT,
                                         p_label             VARCHAR(80) )
  MODIFIES SQL DATA

BEGIN
  DECLARE count_rotors      INT;
  DECLARE count_experiments INT;

  DECLARE duplicate_key TINYINT DEFAULT 0;
  DECLARE null_field    TINYINT DEFAULT 0;

  DECLARE CONTINUE HANDLER FOR 1062
    SET duplicate_key = 1;

  DECLARE CONTINUE HANDLER FOR 1048
    SET null_field = 1;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';
  SET @LAST_INSERT_ID = 0;

  SELECT     COUNT(*)
  INTO       count_rotors
  FROM       rotor
  WHERE      rotorID = p_rotorID;

  SELECT     COUNT(*)
  INTO       count_experiments
  FROM       experiment
  WHERE      experimentID = p_experimentID;

  -- Special value -1
  IF ( p_experimentID = -1 ) THEN
    SET count_experiments = 1;
  END IF;

  IF ( ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN         ) = @OK ) &&
       ( check_GUID      ( p_personGUID, p_password, p_calibrationGUID  ) = @OK ) ) THEN
    IF ( count_rotors < 1 ) THEN
      SET @US3_LAST_ERRNO = @NO_ROTOR;
      SET @US3_LAST_ERROR = CONCAT('MySQL: No rotor with ID ',
                                   p_rotorID,
                                   ' exists' );

    ELSEIF ( count_experiments < 1 ) THEN
      SET @US3_LAST_ERRNO = @NO_EXPERIMENT;
      SET @US3_LAST_ERROR = CONCAT('MySQL: No experiment with ID ',
                                   p_experimentID,
                                   ' exists' );

    ELSE
      INSERT INTO rotorCalibration SET
        rotorID                 = p_rotorID,
        rotorCalibrationGUID    = p_calibrationGUID,
        label                   = p_label,
        report                  = p_report,
        coeff1                  = p_coeff1,
        coeff2                  = p_coeff2,
        omega2_t                = p_omega2_t,
        dateUpdated             = NOW(),
        calibrationExperimentID = p_experimentID;
        
      IF ( duplicate_key = 1 ) THEN
        SET @US3_LAST_ERRNO = @INSERTDUP;
        SET @US3_LAST_ERROR = "MySQL: Duplicate entry for rotorCalibrationGUID field";
  
      ELSEIF ( null_field = 1 ) THEN
        SET @US3_LAST_ERRNO = @INSERTNULL;
        SET @US3_LAST_ERROR = "MySQL: NULL value for rotorCalibrationGUID field";
  
      ELSE
        SET @LAST_INSERT_ID = LAST_INSERT_ID();
  
      END IF;

    END IF;

  END IF;

  SELECT @US3_LAST_ERRNO AS status;

END$$

-- Translate a rotorCalibrationGUID into a rotorCalibrationID
DROP PROCEDURE IF EXISTS get_rotorCalibrationID_from_GUID$$
CREATE PROCEDURE get_rotorCalibrationID_from_GUID ( p_rotorGUID   CHAR(36),
                                                    p_password     VARCHAR(80),
                                                    p_lookupGUID   CHAR(36) )
  READS SQL DATA

BEGIN
  DECLARE count_profile INT;
  DECLARE l_rotorCalibrationID     INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_profile
  FROM       rotorCalibration
  WHERE      rotorCalibrationGUID = p_lookupGUID;

  IF ( count_profile = 0 ) THEN
    SET @US3_LAST_ERRNO = @NOROWS;
    SET @US3_LAST_ERROR = 'MySQL: no rows returned';

    SELECT @US3_LAST_ERRNO AS status;

  ELSE
    SELECT rotorCalibrationID
    INTO   l_rotorCalibrationID
    FROM   rotorCalibration
    WHERE  rotorCalibrationGUID = p_lookupGUID
    LIMIT  1;                           -- should be only 1

    SELECT @OK AS status;

    SELECT l_rotorCalibrationID AS rotorCalibrationID;

  END IF;

END$$

-- DELETEs an individual rotor calibration, unless it is used in an experiment
DROP PROCEDURE IF EXISTS delete_rotor_calibration$$
CREATE PROCEDURE delete_rotor_calibration ( p_personGUID   CHAR(36),
                                            p_password     VARCHAR(80),
                                            p_rotor_calibrationID   INT )
  MODIFIES SQL DATA

BEGIN
  DECLARE count_experiments          INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_experiments
  FROM       experiment
  WHERE      rotorCalibrationID = p_rotor_calibrationID;

  IF ( ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) ) THEN
    IF ( count_experiments > 0 ) THEN
      -- There are experiments that use this calibration profile
      SET @US3_LAST_ERRNO = @CALIB_IN_USE;
      SET @US3_LAST_ERROR = CONCAT( "MySQL: the rotor calibration profile is in use, ",
                                    "and cannot be deleted\n" );

    ELSE
      -- We are verified as an admin, and no experiments with this
      -- rotorCalibrationID exist
      DELETE FROM rotorCalibration
      WHERE       rotorCalibrationID   = p_rotor_calibrationID;
        
    END IF;

  END IF;

  SELECT @US3_LAST_ERRNO AS status;

END$$

-- replaces an individual rotor calibration with another, unless the calibrationID
--  doesn't exist. Used when the original dummy calibration is being replaced
DROP PROCEDURE IF EXISTS replace_rotor_calibration$$
CREATE PROCEDURE replace_rotor_calibration ( p_personGUID   CHAR(36),
                                             p_password     VARCHAR(80),
                                             p_old_calibrationID   INT,
                                             p_new_calibrationID   INT )
  MODIFIES SQL DATA

BEGIN
  DECLARE count_experiments          INT;
  DECLARE count_calibrations         INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_experiments
  FROM       experiment
  WHERE      rotorCalibrationID = p_old_calibrationID;

  SELECT     COUNT(*)
  INTO       count_calibrations
  FROM       rotorCalibration
  WHERE      rotorCalibrationID = p_new_calibrationID;

  IF ( ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) ) THEN
    IF ( count_calibrations = 0 ) THEN
      -- We are verified as an admin, but no calibration by that ID exists
      SET @US3_LAST_ERRNO = @NO_CALIB;
      SET @US3_LAST_ERROR = "MySQL: The new calibration does not exist\n";

    ELSEIF ( count_experiments > 0 ) THEN
      -- Experiments with the old rotorCalibrationID exist
      UPDATE experiment SET
        rotorCalibrationID = p_new_calibrationID
      WHERE  rotorCalibrationID = p_old_calibrationID;

    -- ELSE
      -- No records to update, but this is not really an error
        
    END IF;

  END IF;

  SELECT @US3_LAST_ERRNO AS status;

END$$

--
-- Rotor procedures
--

-- Returns the count of all rotors in the lab
DROP FUNCTION IF EXISTS count_rotors$$
CREATE FUNCTION count_rotors ( p_personGUID CHAR(36),
                               p_password   VARCHAR(80),
                               p_labID      INT )
  RETURNS INT
  READS SQL DATA

BEGIN

  DECLARE count_rotors INT;

  CALL config();
  SET count_rotors = 0;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    SELECT    COUNT(*)
    INTO      count_rotors
    FROM      rotor
    WHERE     labID = p_labID;

  END IF;

  RETURN( count_rotors );

END$$

-- SELECTs names of all rotors in the lab
DROP PROCEDURE IF EXISTS get_rotor_names$$
CREATE PROCEDURE get_rotor_names ( p_personGUID CHAR(36),
                                   p_password   VARCHAR(80),
                                   p_labID      INT )
  READS SQL DATA

BEGIN
  DECLARE count_rotors INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    SELECT    COUNT(*)
    INTO      count_rotors
    FROM      rotor
    WHERE     labID = p_labID;

    IF ( count_rotors = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';
 
      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT   rotorID, name
      FROM     rotor
      WHERE    labID = p_labID
      ORDER BY UPPER( name );
 
    END IF;

  END IF;

END$$

-- Returns a more complete list of information about one rotor
DROP PROCEDURE IF EXISTS get_rotor_info$$
CREATE PROCEDURE get_rotor_info ( p_personGUID CHAR(36),
                                  p_password   VARCHAR(80),
                                  p_rotorID    INT )
  READS SQL DATA

BEGIN
  DECLARE count_rotors INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_rotors
  FROM       rotor
  WHERE      rotorID = p_rotorID;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    IF ( count_rotors = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';

      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT   r.rotorGUID, r.name, serialNumber,  
               a.name, r.abstractRotorID, a.abstractRotorGUID, r.labID
      FROM     rotor r, abstractRotor a
      WHERE    r.abstractRotorID = a.abstractRotorID
      AND      rotorID = p_rotorID;

    END IF;

  ELSE
    SELECT @US3_LAST_ERRNO AS status;

  END IF;

END$$

-- adds a new rotor using an abstractRotor
DROP PROCEDURE IF EXISTS add_rotor$$
CREATE PROCEDURE add_rotor ( p_personGUID        CHAR(36),
                             p_password          VARCHAR(80),
                             p_abstractRotorID   INT,
                             p_abstractRotorGUID CHAR(36),
                             p_labID             INT,
                             p_rotorGUID         CHAR(36),
                             p_name              TEXT,
                             p_serialNumber      TEXT )
  MODIFIES SQL DATA

BEGIN
  DECLARE count_abstract_rotors      INT;
  DECLARE count_labs                 INT;
  DECLARE l_abstractRotorID          INT;
  DECLARE l_abstractRotorID_count    INT;
  DECLARE l_abstractRotorGUID        CHAR(36);
  DECLARE l_abstractRotorGUID_count  INT;

  DECLARE duplicate_key TINYINT DEFAULT 0;
  DECLARE null_field    TINYINT DEFAULT 0;

  DECLARE CONTINUE HANDLER FOR 1062
    SET duplicate_key = 1;

  DECLARE CONTINUE HANDLER FOR 1048
    SET null_field = 1;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';
  SET @LAST_INSERT_ID = 0;

  -- User can specify either abstractRotorID or abstractRotorGUID
  SELECT COUNT(*)
  INTO   l_abstractRotorGUID_count
  FROM   abstractRotor
  WHERE  abstractRotorGUID = p_abstractRotorGUID
  LIMIT  1;                         -- should be exactly 1, if p_abstractRotorGUID is supplied

  SELECT COUNT(*)
  INTO   l_abstractRotorID_count
  FROM   abstractRotor
  WHERE  abstractRotorID = p_abstractRotorID
  LIMIT  1;                         -- should be exactly 1, if p_abstractRotorID is supplied

  IF ( l_abstractRotorGUID_count = 1 ) THEN -- prefer the GUID
    SET l_abstractRotorGUID = p_abstractRotorGUID;

    SELECT abstractRotorID
    INTO   l_abstractRotorID
    FROM   abstractRotor
    WHERE  abstractRotorGUID = p_abstractRotorGUID
    LIMIT  1;

  ELSEIF ( l_abstractRotorID_count = 1 ) THEN
    SET l_abstractRotorID = p_abstractRotorID;

    SELECT abstractRotorGUID
    INTO   l_abstractRotorGUID
    FROM   abstractRotor
    WHERE  abstractRotorID = p_abstractRotorID;

  ELSE
    -- rotor doesn't correspond to any abstractRotor
    SET l_abstractRotorID   = 0;
    SET l_abstractRotorGUID = p_abstractRotorGUID;

  END IF;

  SELECT     COUNT(*)
  INTO       count_abstract_rotors
  FROM       abstractRotor
  WHERE      abstractRotorID = l_abstractRotorID;

  SELECT     COUNT(*)
  INTO       count_labs
  FROM       lab
  WHERE      labID = p_labID;

  IF ( ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN   ) = @OK ) &&
       ( check_GUID      ( p_personGUID, p_password, p_rotorGUID  ) = @OK ) ) THEN
    IF ( count_abstract_rotors < 1 ) THEN
      SET @US3_LAST_ERRNO = @NO_ROTOR;
      SET @US3_LAST_ERROR = CONCAT('MySQL: No abstract rotor with ID ',
                                   p_abstractRotorID,
                                   ' and/or GUID ',
                                   p_abstractRotorGUID,
                                   ' exists' );

    ELSEIF ( count_labs < 1 ) THEN
      SET @US3_LAST_ERRNO = @NO_LAB;
      SET @US3_LAST_ERROR = CONCAT('MySQL: No lab with ID ',
                                   p_labID,
                                   ' exists' );

    ELSE
      INSERT INTO rotor SET
        abstractRotorID   = l_abstractRotorID,
        labID             = p_labID,
        name              = p_name,
        rotorGUID         = p_rotorGUID,
        serialNumber      = p_serialNumber;
        
      IF ( duplicate_key = 1 ) THEN
        SET @US3_LAST_ERRNO = @INSERTDUP;
        SET @US3_LAST_ERROR = "MySQL: Duplicate entry for abstractRotorGUID field";
  
      ELSEIF ( null_field = 1 ) THEN
        SET @US3_LAST_ERRNO = @INSERTNULL;
        SET @US3_LAST_ERROR = "MySQL: NULL value for abstractRotorGUID field";
  
      ELSE
        SET @LAST_INSERT_ID = LAST_INSERT_ID();
  
      END IF;

    END IF;

  END IF;

  SELECT @US3_LAST_ERRNO AS status;

END$$

-- Translate a rotorGUID into a rotorID
DROP PROCEDURE IF EXISTS get_rotorID_from_GUID$$
CREATE PROCEDURE get_rotorID_from_GUID ( p_rotorGUID   CHAR(36),
                                         p_password     VARCHAR(80),
                                         p_lookupGUID   CHAR(36) )
  READS SQL DATA

BEGIN
  DECLARE count_rotor  INT;
  DECLARE l_rotorID    INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_rotor
  FROM       rotor
  WHERE      rotorGUID = p_lookupGUID;

  IF ( count_rotor = 0 ) THEN
    SET @US3_LAST_ERRNO = @NOROWS;
    SET @US3_LAST_ERROR = 'MySQL: no rows returned';

    SELECT @US3_LAST_ERRNO AS status;

  ELSE
    SELECT rotorID
    INTO   l_rotorID
    FROM   rotor
    WHERE  rotorGUID = p_lookupGUID
    LIMIT  1;                           -- should be only 1

    SELECT @OK AS status;

    SELECT l_rotorID AS rotorID;

  END IF;

END$$

-- DELETEs an individual rotor, unless it is used in an experiment
-- This should include a rotor calibration experiment, so one test ought to do
DROP PROCEDURE IF EXISTS delete_rotor$$
CREATE PROCEDURE delete_rotor ( p_personGUID   CHAR(36),
                                p_password     VARCHAR(80),
                                p_rotorID      INT )
  MODIFIES SQL DATA

BEGIN
  DECLARE count_experiments          INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_experiments
  FROM       experiment
  WHERE      rotorID = p_rotorID;

  IF ( ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) ) THEN
    IF ( count_experiments > 0 ) THEN
      -- There are experiments that use this rotor
      SET @US3_LAST_ERRNO = @ROTOR_IN_USE;
      SET @US3_LAST_ERROR = CONCAT( "MySQL: the rotor is in use, ",
                                    "and cannot be deleted\n" );

    ELSE
      -- We are verified as an admin, and no experiments with this
      -- rotorID exist
      -- delete calibration first or rotorID will change to NULL
      DELETE FROM rotorCalibration 
      WHERE       rotorID   = p_rotorID;

      DELETE FROM rotor
      WHERE       rotorID   = p_rotorID;
        
    END IF;

  END IF;

  SELECT @US3_LAST_ERRNO AS status;

END$$

-- Get a list of abstract rotor names
DROP PROCEDURE IF EXISTS get_abstractRotor_names$$
CREATE PROCEDURE get_abstractRotor_names ( p_personGUID CHAR(36),
                                           p_password   VARCHAR(80) )
  READS SQL DATA

BEGIN
  DECLARE count_abstract_rotors INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    SELECT    COUNT(*)
    INTO      count_abstract_rotors
    FROM      abstractRotor;

    IF ( count_abstract_rotors = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';
 
      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT   abstractRotorID, name
      FROM     abstractRotor
      ORDER BY UPPER( name );
 
    END IF;

  END IF;

END$$

-- Translate an abstractRotorGUID into an abstractRotorID
DROP PROCEDURE IF EXISTS get_abstractRotorID_from_GUID$$
CREATE PROCEDURE get_abstractRotorID_from_GUID ( p_abstractRotorGUID   CHAR(36),
                                                 p_password     VARCHAR(80),
                                                 p_lookupGUID   CHAR(36) )
  READS SQL DATA

BEGIN
  DECLARE count_abstractRotor  INT;
  DECLARE l_abstractRotorID    INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_abstractRotor
  FROM       abstractRotor
  WHERE      abstractRotorGUID = p_lookupGUID;

  IF ( count_abstractRotor = 0 ) THEN
    SET @US3_LAST_ERRNO = @NOROWS;
    SET @US3_LAST_ERROR = 'MySQL: no rows returned';

    SELECT @US3_LAST_ERRNO AS status;

  ELSE
    SELECT abstractRotorID
    INTO   l_abstractRotorID
    FROM   abstractRotor
    WHERE  abstractRotorGUID = p_lookupGUID
    LIMIT  1;                           -- should be only 1

    SELECT @OK AS status;

    SELECT l_abstractRotorID AS abstractRotorID;

  END IF;

END$$

-- Returns a more complete list of information about one abstractRotor
DROP PROCEDURE IF EXISTS get_abstractRotor_info$$
CREATE PROCEDURE get_abstractRotor_info ( p_personGUID CHAR(36),
                                          p_password   VARCHAR(80),
                                          p_abstractRotorID    INT )
  READS SQL DATA

BEGIN
  DECLARE count_abstractRotors INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_abstractRotors
  FROM       abstractRotor
  WHERE      abstractRotorID = p_abstractRotorID;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    IF ( count_abstractRotors = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';

      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT   abstractRotorGUID, name, materialName, numHoles,
               maxRPM, magnetOffset, cellCenter, manufacturer
      FROM     abstractRotor
      WHERE    abstractRotorID = p_abstractRotorID;

    END IF;

  ELSE
    SELECT @US3_LAST_ERRNO AS status;

  END IF;

END$$

--
-- Lab procedures
--

-- Returns the count of all labs in db
DROP FUNCTION IF EXISTS count_labs$$
CREATE FUNCTION count_labs ( p_personGUID CHAR(36),
                             p_password   VARCHAR(80) )
  RETURNS INT
  READS SQL DATA

BEGIN

  DECLARE count_labs INT;

  CALL config();
  SET count_labs = 0;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    SELECT    COUNT(*)
    INTO      count_labs
    FROM      lab;

  END IF;

  RETURN( count_labs );

END$$

-- SELECTs names of all labs
DROP PROCEDURE IF EXISTS get_lab_names$$
CREATE PROCEDURE get_lab_names ( p_personGUID CHAR(36),
                                 p_password   VARCHAR(80) )
  READS SQL DATA

BEGIN
  DECLARE count_labs INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    SELECT    COUNT(*)
    INTO      count_labs
    FROM      lab;

    IF ( count_labs = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';
 
      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT labID, name
      FROM lab
      ORDER BY name;
 
    END IF;

  END IF;

END$$

-- Returns a more complete list of information about one lab
DROP PROCEDURE IF EXISTS get_lab_info$$
CREATE PROCEDURE get_lab_info ( p_personGUID CHAR(36),
                                p_password   VARCHAR(80),
                                p_labID      INT )
  READS SQL DATA

BEGIN
  DECLARE count_labs INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_labs
  FROM       lab
  WHERE      labID = p_labID;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    IF ( count_labs = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';

      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT   labGUID, name, building, room
      FROM     lab
      WHERE    labID = p_labID;

    END IF;

  ELSE
    SELECT @US3_LAST_ERRNO AS status;

  END IF;

END$$

-- adds a new lab
DROP PROCEDURE IF EXISTS add_lab$$
CREATE PROCEDURE add_lab ( p_personGUID        CHAR(36),
                           p_password          VARCHAR(80),
                           p_labGUID           CHAR(36),
                           p_name              TEXT,
                           p_building          TEXT,
                           p_room              TEXT )
  MODIFIES SQL DATA

BEGIN
  DECLARE duplicate_key TINYINT DEFAULT 0;
  DECLARE null_field    TINYINT DEFAULT 0;

  DECLARE CONTINUE HANDLER FOR 1062
    SET duplicate_key = 1;

  DECLARE CONTINUE HANDLER FOR 1048
    SET null_field = 1;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';
  SET @LAST_INSERT_ID = 0;

  IF ( ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) &&
       ( check_GUID      ( p_personGUID, p_password, p_labGUID  ) = @OK ) ) THEN
    INSERT INTO lab SET
      labGUID           = p_labGUID,
      name              = p_name,
      building          = p_building,
      room              = p_room,
      dateUpdated       = NOW();

    IF ( duplicate_key = 1 ) THEN
      SET @US3_LAST_ERRNO = @INSERTDUP;
      SET @US3_LAST_ERROR = "MySQL: Duplicate entry for labGUID field";

    ELSEIF ( null_field = 1 ) THEN
      SET @US3_LAST_ERRNO = @INSERTNULL;
      SET @US3_LAST_ERROR = "MySQL: NULL value for labGUID field";

    ELSE
      SET @LAST_INSERT_ID = LAST_INSERT_ID();

    END IF;

  END IF;

  SELECT @US3_LAST_ERRNO AS status;

END$$

-- Translate a labGUID into a labID
DROP PROCEDURE IF EXISTS get_labID_from_GUID$$
CREATE PROCEDURE get_labID_from_GUID ( p_labGUID      CHAR(36),
                                       p_password     VARCHAR(80),
                                       p_lookupGUID   CHAR(36) )
  READS SQL DATA

BEGIN
  DECLARE count_lab  INT;
  DECLARE l_labID    INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_lab
  FROM       lab
  WHERE      labGUID = p_lookupGUID;

  IF ( count_lab = 0 ) THEN
    SET @US3_LAST_ERRNO = @NOROWS;
    SET @US3_LAST_ERROR = 'MySQL: no rows returned';

    SELECT @US3_LAST_ERRNO AS status;

  ELSE
    SELECT labID
    INTO   l_labID
    FROM   lab
    WHERE  labGUID = p_lookupGUID
    LIMIT  1;                           -- should be only 1

    SELECT @OK AS status;

    SELECT l_labID AS labID;

  END IF;

END$$

--
-- Instrument procedures
--

-- Returns the count of all instruments in db
DROP FUNCTION IF EXISTS count_instruments$$
CREATE FUNCTION count_instruments ( p_personGUID CHAR(36),
                                    p_password   VARCHAR(80),
                                    p_labID      INT )
  RETURNS INT
  READS SQL DATA

BEGIN

  DECLARE count_instruments INT;

  CALL config();
  SET count_instruments = 0;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    SELECT    COUNT(*)
    INTO      count_instruments
    FROM      instrument
    WHERE     labID = p_labID;

  END IF;

  RETURN( count_instruments );

END$$

-- SELECTs names of all instruments
DROP PROCEDURE IF EXISTS get_instrument_names$$
CREATE PROCEDURE get_instrument_names ( p_personGUID CHAR(36),
                                        p_password   VARCHAR(80),
                                        p_labID      INT )
  READS SQL DATA

BEGIN
  DECLARE count_instruments INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    SELECT    COUNT(*)
    INTO      count_instruments
    FROM      instrument
    WHERE     labID = p_labID;

    IF ( count_instruments = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';
 
      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT   instrumentID, name, selected 
      FROM     instrument
      WHERE    labID = p_labID 
      ORDER BY name;
 
    END IF;

  END IF;

END$$

-- Returns a more complete list of information about one instrument
DROP PROCEDURE IF EXISTS get_instrument_info$$
CREATE PROCEDURE get_instrument_info ( p_personGUID    CHAR(36),
                                       p_password      VARCHAR(80),
                                       p_instrumentID  INT )
  READS SQL DATA

BEGIN
  DECLARE count_instruments INT;
  DECLARE count_rcal_instrs INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_instruments
  FROM       instrument
  WHERE      instrumentID = p_instrumentID;

  SELECT     COUNT(*)
  INTO       count_rcal_instrs
  FROM       instrument ins, radialCalibration rac
  WHERE      ins.instrumentID = p_instrumentID
  AND        rac.radialCalID = ins.radialCalID;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    IF ( count_instruments = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';

      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      IF ( count_rcal_instrs = 0 ) THEN
        SELECT   name, serialNumber, labID, dateUpdated, radialCalID
        FROM     instrument
        WHERE    instrumentID = p_instrumentID;

      ELSE
        SELECT   name, serialNumber, labID, dateUpdated, radialCalID,
                 rac.speed, rac.rotorCalID, roc.coeff1, roc.coeff2
        FROM     instrument ins, radialCalibration rac, rotorCalibration roc
        WHERE    instrumentID = p_instrumentID
        AND      rac.radialCalID = ins.radialCalID
        AND      roc.rotorCalibrationID = rac.rotorCalID ;

      END IF;

    END IF;

  ELSE
    SELECT @US3_LAST_ERRNO AS status;

  END IF;

END$$


-- Returns a more complete list of information about one instrument including connection, optimaDB name etc.
DROP PROCEDURE IF EXISTS get_instrument_info_new$$
CREATE PROCEDURE get_instrument_info_new ( p_personGUID    CHAR(36),
                                       p_password      VARCHAR(80),
                                       p_instrumentID  INT )
  READS SQL DATA

BEGIN
  DECLARE count_instruments INT;
  DECLARE count_rcal_instrs INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_instruments
  FROM       instrument
  WHERE      instrumentID = p_instrumentID;

  SELECT     COUNT(*)
  INTO       count_rcal_instrs
  FROM       instrument ins, radialCalibration rac
  WHERE      ins.instrumentID = p_instrumentID
  AND        rac.radialCalID = ins.radialCalID;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    IF ( count_instruments = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';

      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      IF ( count_rcal_instrs = 0 ) THEN
        SELECT   name, serialNumber, labID, dateUpdated, radialCalID, 
	         optimaHost, optimaPort, optimaDBname, optimaDBusername, 
		 DECODE(optimaDBpassw,'secretOptimaDB'), selected, opsys1, opsys2, opsys3, RadCalWvl, chromaticAB
        FROM     instrument
        WHERE    instrumentID = p_instrumentID;

      ELSE
        SELECT   name, serialNumber, labID, dateUpdated, radialCalID,
                 rac.speed, rac.rotorCalID, roc.coeff1, roc.coeff2
        FROM     instrument ins, radialCalibration rac, rotorCalibration roc
        WHERE    instrumentID = p_instrumentID
        AND      rac.radialCalID = ins.radialCalID
        AND      roc.rotorCalibrationID = rac.rotorCalID ;

      END IF;

    END IF;

  ELSE
    SELECT @US3_LAST_ERRNO AS status;

  END IF;

END$$

-- adds a new instrument
DROP PROCEDURE IF EXISTS add_instrument$$
CREATE PROCEDURE add_instrument ( p_personGUID    CHAR(36),
                                  p_password      VARCHAR(80),
                                  p_name          TEXT,
                                  p_serialNumber  TEXT,
                                  p_labID         INT )
  MODIFIES SQL DATA

BEGIN
  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';
  SET @LAST_INSERT_ID = 0;

  IF ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) THEN
    INSERT INTO instrument SET
      name              = p_name,
      serialNumber      = p_serialNumber,
      labID             = p_labID,
      dateUpdated       = NOW();

    SET @LAST_INSERT_ID = LAST_INSERT_ID();

  END IF;

  SELECT @US3_LAST_ERRNO AS status;

END$$


-- adds a new instrument with more information
DROP PROCEDURE IF EXISTS add_instrument_new$$
CREATE PROCEDURE add_instrument_new ( p_personGUID    CHAR(36),
                                    p_password      VARCHAR(80),
                                    p_name          TEXT,
                                    p_serialNumber  TEXT,
                                    p_labID         INT,
				    p_host          TEXT,
				    p_port          INT,
        			    p_optimadbname  TEXT,
				    p_optimadbuser  TEXT,
				    p_optimadbpassw  VARCHAR(100),
				    p_opsys1        TEXT,
                                    p_opsys2        TEXT,
                                    p_opsys3        TEXT,
				    p_radcalwvl     INT,
                                    p_chromoab      TEXT )

  MODIFIES SQL DATA

BEGIN
  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';
  SET @LAST_INSERT_ID = 0;

  IF ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) THEN
    INSERT INTO instrument SET
      name              = p_name,
      serialNumber      = p_serialNumber,
      labID             = p_labID,
      optimaHost        = p_host,
      optimaPort        = p_port,
      optimaDBname      = p_optimadbname,
      optimaDBusername  = p_optimadbuser,
      optimaDBpassw     = ENCODE( p_optimadbpassw, 'secretOptimaDB' ),
      opsys1            = p_opsys1,
      opsys2		= p_opsys2,
      opsys3            = p_opsys3,
      RadCalWvl         = p_radcalwvl,
      chromaticAB       = p_chromoab,
      dateUpdated       = NOW();

    SET @LAST_INSERT_ID = LAST_INSERT_ID();

  END IF;

  SELECT @US3_LAST_ERRNO AS status;

END$$

-- UPDATEs an existing instrument with radial calibration ID information
DROP PROCEDURE IF EXISTS update_instrument$$
CREATE PROCEDURE update_instrument ( p_personGUID    CHAR(36),
                                     p_password      VARCHAR(80),
                                     p_instrumentID  INT,
                                     p_radialCalID   INT(11) )
  MODIFIES SQL DATA

BEGIN

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) THEN

    UPDATE instrument SET radialCalID = p_radialCalID
    WHERE instrumentID = p_instrumentID;

  END IF;
      
  SELECT @US3_LAST_ERRNO AS status;

END$$


-- UPDATEs an existing instrument                                                                                                    
DROP PROCEDURE IF EXISTS update_instrument_new$$
CREATE PROCEDURE update_instrument_new ( p_personGUID    CHAR(36),
                                       p_password      VARCHAR(80),
                                       p_instrumentID  INT,
                                       p_name          TEXT,
                                       p_serialNumber  TEXT,
                                       p_labID         INT,
                                       p_host          TEXT,
                                       p_port          INT,
                                       p_optimadbname  TEXT,
                                       p_optimadbuser  TEXT,
                                       p_optimadbpassw  VARCHAR(100),
				       p_opsys1        TEXT,
				       p_opsys2        TEXT,
				       p_opsys3        TEXT,
				       p_radcalwvl     INT,
				       p_chromoab      TEXT )

  MODIFIES SQL DATA

BEGIN

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) THEN

    UPDATE instrument SET 
      name              = p_name,
      serialNumber      = p_serialNumber,
      labID             = p_labID,
      optimaHost        = p_host,
      optimaPort        = p_port,
      optimaDBname      = p_optimadbname,
      optimaDBusername  = p_optimadbuser,
      optimaDBpassw     = ENCODE( p_optimadbpassw, 'secretOptimaDB' ),
      opsys1            = p_opsys1,
      opsys2            = p_opsys2,
      opsys3            = p_opsys3,	
      RadCalWvl         = p_radcalwvl,
      chromaticAB       = p_chromoab,
      dateUpdated       = NOW()
    WHERE instrumentID = p_instrumentID;

  END IF;

  SELECT @US3_LAST_ERRNO AS status;

END$$


-- UPDATEs an existing instrument: set selected
DROP PROCEDURE IF EXISTS update_instrument_set_selected$$
CREATE PROCEDURE update_instrument_set_selected ( p_personGUID    CHAR(36),
                                     p_password      VARCHAR(80),
                                     p_name          TEXT )
  MODIFIES SQL DATA

BEGIN

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) THEN

    UPDATE instrument SET selected = 1 
    WHERE name = p_name;

  END IF;
      
  SELECT @US3_LAST_ERRNO AS status;

END$$

-- UPDATEs an existing instrument: set unselected
DROP PROCEDURE IF EXISTS update_instrument_set_unselected$$
CREATE PROCEDURE update_instrument_set_unselected ( p_personGUID    CHAR(36),
                                     p_password      VARCHAR(80),
                                     p_name          TEXT )
  MODIFIES SQL DATA

BEGIN

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) THEN

    UPDATE instrument SET selected = 0  
    WHERE name = p_name;

  END IF;
      
  SELECT @US3_LAST_ERRNO AS status;

END$$


-- DELETE  existing instrument:
DROP PROCEDURE IF EXISTS delete_instrument$$
CREATE PROCEDURE delete_instrument ( p_personGUID    CHAR(36),
                                     p_password      VARCHAR(80),
                                     p_instrumentID  INT )
  MODIFIES SQL DATA

BEGIN
  DECLARE count_instruments INT;	
	
  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN  ) = @OK ) THEN
    
    -- Find out if this instrument is used in any experiment first
    SELECT COUNT(*) INTO count_instruments 
    FROM experiment 
    WHERE instrumentID = p_instrumentID;

    IF ( count_instruments = 0 ) THEN
       DELETE FROM instrument
       WHERE instrumentID = p_instrumentID;

    ELSE
      SET @US3_LAST_ERRNO = @INSTRUMENT_IN_USE;
      SET @US3_LAST_ERROR = 'The instrument is in use in experiment';   
    
    END IF;  

  END IF;
      
  SELECT @US3_LAST_ERRNO AS status;

END$$

-- ENCODE instrument's DB password:
DROP PROCEDURE IF EXISTS decode_instrument_passw$$
CREATE PROCEDURE decode_instrument_passw ( p_personGUID    CHAR(36),
                                     	  p_password      VARCHAR(80),
                                     	   p_instrumentID  INT )
  READS SQL DATA

BEGIN

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) THEN

    SELECT DECODE(optimaDBpassw,'secretOptimaDB') FROM instrument
    WHERE instrumentID = p_instrumentID;

  END IF;
      
  SELECT @US3_LAST_ERRNO AS status;
  
END$$

-- Get ID of the selected instrument ---
DROP PROCEDURE IF EXISTS get_instrument_selected$$
CREATE PROCEDURE get_instrument_selected ( p_personGUID    CHAR(36),
                                           p_password      VARCHAR(80),
					   p_selected      TINYINT )
                                     	       
  READS SQL DATA

BEGIN

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN ) = @OK ) THEN

    SELECT instrumentID FROM instrument WHERE selected = p_selected;

  END IF;
      
  SELECT @US3_LAST_ERRNO AS status;

END$$


-- SELECTs names of all operators permitted to operate a specified instrument
DROP PROCEDURE IF EXISTS get_operator_names$$
CREATE PROCEDURE get_operator_names ( p_personGUID   CHAR(36),
                                      p_password     VARCHAR(80),
                                      p_instrumentID INT )
  READS SQL DATA

BEGIN
  DECLARE count_operators INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    SELECT    COUNT(*)
    INTO      count_operators
    FROM      permits
    WHERE     instrumentID = p_instrumentID;

    IF ( count_operators = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';
 
      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT   m.personID, p.personGUID, p.lname, p.fname
      FROM     permits m, people p
      WHERE    m.instrumentID = p_instrumentID 
      AND      m.personID = p.personID
      ORDER BY p.lname, p.fname;
 
    END IF;

  END IF;

END$$

--
-- Centerpiece procedures
--

-- SELECTs names of all abstract centerpieces
DROP PROCEDURE IF EXISTS get_abstractCenterpiece_names$$
CREATE PROCEDURE get_abstractCenterpiece_names ( p_personGUID CHAR(36),
                                                 p_password   VARCHAR(80) )
  READS SQL DATA

BEGIN
  DECLARE count_abstract_centerpieces INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    SELECT    COUNT(*)
    INTO      count_abstract_centerpieces
    FROM      abstractCenterpiece;

    IF ( count_abstract_centerpieces = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';
 
      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT abstractCenterpieceID, name
      FROM abstractCenterpiece
      ORDER BY name;
 
    END IF;

  END IF;

END$$

-- Returns a more complete list of information about one centerpiece
DROP PROCEDURE IF EXISTS get_abstractCenterpiece_info$$
CREATE PROCEDURE get_abstractCenterpiece_info ( p_personGUID CHAR(36),
                                                p_password   VARCHAR(80),
                                                p_abstractCenterpieceID  INT )
  READS SQL DATA

BEGIN
  DECLARE count_abstract_centerpieces INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  SELECT     COUNT(*)
  INTO       count_abstract_centerpieces
  FROM       abstractCenterpiece
  WHERE      abstractCenterpieceID = p_abstractCenterpieceID;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    IF ( count_abstract_centerpieces = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';

      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      SELECT   abstractCenterpieceGUID, name, channels, bottom, shape,
               maxRPM, pathLength, angle, width
      FROM     abstractCenterpiece
      WHERE    abstractCenterpieceID = p_abstractCenterpieceID;

    END IF;

  ELSE
    SELECT @US3_LAST_ERRNO AS status;

  END IF;

END$$


--
-- Radial Calibration procedures
--

-- adds a new radial calibration profile
DROP PROCEDURE IF EXISTS add_radialcal$$
CREATE PROCEDURE add_radialcal ( p_personGUID      CHAR(36),
                                 p_password        VARCHAR(80),
                                 p_radialCalGUID   CHAR(36),
                                 p_speed           INT,
                                 p_rotorCalID      INT )
  MODIFIES SQL DATA

BEGIN
  DECLARE count_rotorcals   INT;

  DECLARE duplicate_key TINYINT DEFAULT 0;
  DECLARE null_field    TINYINT DEFAULT 0;

  DECLARE CONTINUE HANDLER FOR 1062
    SET duplicate_key = 1;

  DECLARE CONTINUE HANDLER FOR 1048
    SET null_field = 1;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';
  SET @LAST_INSERT_ID = 0;

  SELECT     COUNT(*)
  INTO       count_rotorcals
  FROM       rotorCalibration
  WHERE      rotorCalibrationID = p_rotorCalID;

  IF ( ( verify_userlevel( p_personGUID, p_password, @US3_ADMIN       ) = @OK ) &&
       ( check_GUID      ( p_personGUID, p_password, p_radialCalGUID  ) = @OK ) ) THEN
    IF ( count_rotorcals < 1 ) THEN
      SET @US3_LAST_ERRNO = @NO_ROTOR_CAL;
      SET @US3_LAST_ERROR = CONCAT('MySQL: No rotor calibration with ID ',
                                   p_rotorCalID,
                                   ' exists' );

    ELSE
      INSERT INTO radialCalibration SET
        radialCalGUID   = p_radialCalGUID,
        speed           = p_speed,
        rotorCalID      = p_rotorCalID,
        dateUpdated     = NOW() ;
        
      IF ( duplicate_key = 1 ) THEN
        SET @US3_LAST_ERRNO = @INSERTDUP;
        SET @US3_LAST_ERROR = "MySQL: Duplicate entry for radialCalGUID field";
  
      ELSEIF ( null_field = 1 ) THEN
        SET @US3_LAST_ERRNO = @INSERTNULL;
        SET @US3_LAST_ERROR = "MySQL: NULL value for radialCalGUID field";
  
      ELSE
        SET @LAST_INSERT_ID = LAST_INSERT_ID();
  
      END IF;

    END IF;

  END IF;

  SELECT @US3_LAST_ERRNO AS status;

END$$

-- Returns information about one or all radial calibration profile(s)
DROP PROCEDURE IF EXISTS get_radialcal_info$$
CREATE PROCEDURE get_radialcal_info ( p_personGUID  CHAR(36),
                                      p_password    VARCHAR(80),
                                      p_radialCalID INT )
  READS SQL DATA

BEGIN
  DECLARE count_profiles INT;

  CALL config();
  SET @US3_LAST_ERRNO = @OK;
  SET @US3_LAST_ERROR = '';

  IF ( p_radialCalID > 0 ) THEN
    SELECT     COUNT(*)
    INTO       count_profiles
    FROM       radialCalibration
    WHERE      radialCalID = p_radialCalID;
  ELSE
    SELECT     COUNT(*)
    INTO       count_profiles
    FROM       radialCalibration;
  END IF;

  IF ( verify_user( p_personGUID, p_password ) = @OK ) THEN
    IF ( count_profiles = 0 ) THEN
      SET @US3_LAST_ERRNO = @NOROWS;
      SET @US3_LAST_ERROR = 'MySQL: no rows returned';

      SELECT @US3_LAST_ERRNO AS status;

    ELSE
      SELECT @OK AS status;

      IF ( p_radialCalID > 0 ) THEN
        SELECT   radialCalID, radialCalGUID, speed, rotorCalID, dateUpdated,
                 roc.coeff1, roc.coeff2
        FROM     radialCalibration, rotorCalibration roc
        WHERE    radialCalID = p_radialCalID
        AND      roc.rotorCalibrationID = rotorCalID ;
      ELSE
        SELECT   radialCalID, radialCalGUID, speed, rotorCalID, dateUpdated,
                 roc.coeff1, roc.coeff2
        FROM     radialCalibration, rotorCalibration roc
        WHERE    roc.rotorCalibrationID = rotorCalID ;
      END IF;

    END IF;

  ELSE
    SELECT @US3_LAST_ERRNO AS status;

  END IF;

END$$

DELIMITER ;

