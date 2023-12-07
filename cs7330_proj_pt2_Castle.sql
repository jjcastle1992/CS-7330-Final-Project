-- Name: James  Castle
-- Class: CS 7330 Sec 401 Fall 2023
-- SMU ID: 29248132
-- Final Project Part 2

-- create database
DROP DATABASE IF EXISTS `cs7330_project_pt2`;
CREATE DATABASE `cs7330_project_pt2`;
USE cs7330_project_pt2;

-- Create Tables Inspections and Inspectors
CREATE TABLE Inspectors (
    inspector_id INT UNSIGNED PRIMARY KEY CHECK(inspector_id BETWEEN 100 AND 999), -- validate that this is a 3 digit num in final version
    inspector_name VARCHAR(255) NOT NULL,
    hire_date DATE NOT NULL
);

CREATE TABLE Inspection_Types
(
    code VARCHAR(3) PRIMARY KEY NOT NULL,
    type VARCHAR(50) NOT NULL,
    prereq_1 VARCHAR(50),
    prereq_2 VARCHAR(50),  -- Use 2 pre-req because notice all inspections have between 0 - 2 prereqs and don't know how to get fancier yet.
    cost INT NOT NULL,
    old_cost INT DEFAULT NULL, -- used to capture old costs new inspections before eff date
    eff_date DATE NOT NULL
);

CREATE TABLE Builders
(
    license_no INT PRIMARY KEY CHECK(license_no BETWEEN 10000 AND 99999),
    name VARCHAR(255) UNIQUE NOT NULL,
    address VARCHAR(255) NOT NULL
);

CREATE TABLE locations
(
    id INT PRIMARY KEY AUTO_INCREMENT,
    address VARCHAR(255) NOT NULL,
    builder INT NOT NULL,
    FOREIGN KEY (builder)
        REFERENCES Builders (license_no),
    type ENUM('commercial','residential'),
    size INT,
    date_first_act DATE
);

CREATE TABLE Inspections (
    inspection_id INT PRIMARY KEY AUTO_INCREMENT,
    inspection_date DATE NOT NULL,
    inspector_id INT UNSIGNED NOT NULL,
    FOREIGN KEY (inspector_id)
        REFERENCES Inspectors (inspector_id),
    building VARCHAR(255),  -- check that address exists with trigger
    type VARCHAR(50) NOT NULL,
    FOREIGN KEY (type)
        REFERENCES Inspection_Types (code),
    insp_score INT CHECK( insp_score BETWEEN 0 AND 100),  -- insert check for valid score range in final version
    insp_notes VARCHAR(255),
    insp_cost INT  -- write in with a trigger
);

# *****TRIGGERS******
-- Create Trigger to ensure building and builder exists before an inspection can  be scheduled
DELIMITER $$
CREATE TRIGGER new_inspection_loc_and_builder_valid
    BEFORE INSERT ON Inspections
    FOR EACH ROW
    BEGIN
        DECLARE location_id INT;
        DECLARE builder_id INT;
        DECLARE lic_no INT;

        -- Check if the address exists in the locations table
        SELECT id, builder INTO location_id, builder_id FROM locations WHERE address = NEW.building;
        -- Reject if it doesn't exist
        IF location_id IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Attempted to schedule an inspection for a location that does not yet exist';
        END IF;


        -- Check if the builder is in the builders table
        SELECT license_no INTO lic_no FROM Builders WHERE license_no = builder_id;

        IF lic_no IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Attempted to schedule an inspection for a builder that does not yet exist';
        END IF;

    END$$
DELIMITER ;

-- Create trigger to set cost of an inspection from the latest inspection_types cost sheet
DELIMITER $$
CREATE TRIGGER new_inspection_cost
    BEFORE INSERT ON Inspections
    FOR EACH ROW
    BEGIN
        DECLARE type_cost INT;

        SELECT cost INTO type_cost
        FROM Inspection_Types
        WHERE code  = NEW.type;

        SET NEW.insp_cost = type_cost;

    END$$
DELIMITER ;

-- Create trigger to update inspection type table with historical cost. Then update any inspections occurring after eff date
DELIMITER $$
CREATE TRIGGER update_inspection_cost
    BEFORE UPDATE ON Inspection_Types
    FOR EACH ROW
    BEGIN
        -- set historical cost
        IF NEW.code = NEW.code THEN
           SET NEW.old_cost = OLD.cost;
        END IF;

        -- update inspections scheduled after effective date
        IF NEW.eff_date > OLD.eff_date THEN
            UPDATE Inspections
                SET insp_cost = NEW.cost
                WHERE type = NEW.code AND inspection_date >= NEW.eff_date;
        END IF;
    END$$
DELIMITER ;


-- Create a trigger that ensures an inspection is assigned to an inspector who was hired before date of inspection
DELIMITER $$
CREATE TRIGGER inspector_valid_hire_and_num_insp
    BEFORE INSERT ON Inspections
    FOR EACH ROW
    BEGIN
        -- Check for valid hire date
        DECLARE inspector INT;
        DECLARE inspection_count INT;
        SET inspector = (
            SELECT Inspectors.inspector_id
            FROM Inspectors
            WHERE hire_date < NEW.inspection_date
            LIMIT 1);
        IF inspector IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Inspector must have been hired prior to the inspection date';
        END IF;

        -- Check for 4 or fewer inspections in a month
        SELECT COUNT(*)
        INTO inspection_count
        FROM Inspections
        WHERE inspector_id = NEW.inspector_id
            AND YEAR(inspection_date) = YEAR(NEW.inspection_date)
            AND MONTH(inspection_date) = MONTH(NEW.inspection_date);

        IF inspection_count > 4 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Inspector already scheduled for 5 inspections this month';
        END IF;
    END$$
DELIMITER ;

-- Create Trigger to Ensure score is read-only once written
DELIMITER $$
CREATE TRIGGER prevent_update_insp_score
BEFORE UPDATE ON Inspections
FOR EACH ROW
BEGIN
    IF NEW.insp_score <> OLD.insp_score THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: The score cannot be updated once entered';
    END IF;
END$$
DELIMITER ;

# Testing Read-Only score
# UPDATE Inspections
# SET insp_score = 42
# WHERE inspection_id = 30;

-- Create a trigger for pre-requisites ensuring a passing score in a needed pre-requisite
DELIMITER $$
CREATE TRIGGER check_prereqs
BEFORE INSERT ON Inspections
FOR EACH ROW
BEGIN
    DECLARE prereq CHAR(3);
    DECLARE prereq_score INT;
    DECLARE second_preq CHAR(3);
    DECLARE prereq_score2 INT;

    -- Discover if there's a pre-req
    SELECT prereq_1, prereq_2 INTO prereq, second_preq
    FROM Inspection_Types AS T
    WHERE T.code = NEW.type;

    -- Check if prereq inspection occurred AND PASSED
    IF prereq IS NOT NULL THEN
        SELECT MAX(insp_score) INTO prereq_score
        FROM Inspections AS I
        WHERE (I.building = NEW.building AND I.type = prereq AND I.insp_score > 74);

        IF prereq_score IS NULL THEN  -- If Fail, return error
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: A pre-requisite must be passed prior to this inspection being allowed';
        END IF;

        -- If pass, check for a second pre-req
        IF second_preq IS NOT NULL THEN
            SELECT MAX(insp_score) into prereq_score2
            FROM Inspections AS I
            WHERE (I.building = NEW.building AND I.type = second_preq AND I.insp_score > 74);

            IF prereq_score2 IS NULL THEN  -- If Fail, return error
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: A second pre-requisite must be passed prior to this inspection being allowed';
            END IF;
        END IF;
    END IF;
END$$
DELIMITER ;

TRUNCATE inspections;

# INSERT INTO locations (address, builder, type, size) VALUE ('Fake Ln', 12345, 'residential', 42);
# -- Good insert (Fail FRM)
# INSERT INTO Inspections (inspection_date, inspector_id, building, type, insp_score, insp_notes)
#     VALUE ('2023-12-06', 101, 'Fake Ln', 'FRM', 42, 'Failed Framing');
#
# -- Bad insert (PLU before passed FRM )
# INSERT INTO Inspections (inspection_date, inspector_id, building, type, insp_score, insp_notes)
#     VALUE ('2023-12-06', 101, 'Fake Ln', 'PLU', 100, 'ERROR: did not pass framing');

# ******Part 2 SQL Questions*******
-- 1.List all buildings (assume builder#, address, type) that do not have a final (FNL, FN2, FN3) inspection.
SELECT loc.builder, loc.address, MAX(loc.type) as type
FROM Inspections AS ins
JOIN locations AS loc ON ins.building = loc.address
WHERE loc.builder NOT IN (
    SELECT DISTINCT loc.builder
    FROM Inspections AS ins
    JOIN locations AS loc ON ins.building = loc.address
    WHERE ins.type IN ('FNL', 'FN2', 'FN3')
)
GROUP BY loc.builder, loc.address;

-- 2.	List the id and name of inspectors who have given at least one failing score.
SELECT DISTINCT I.inspector_id, S.inspector_name
FROM Inspections AS I
JOIN Inspectors AS S ON I.inspector_id = S.inspector_id
WHERE insp_score < 75;

-- 3.	What inspection type(s) have never been failed?
SELECT DISTINCT type
FROM inspections
WHERE type NOT IN (
    SELECT type
    FROM inspections
    WHERE insp_score < 75
);
-- 4.	What is the total cost of all inspections for builder 12345?
SELECT loc.builder, SUM(insp_cost)
FROM inspections AS isp
JOIN locations AS loc ON isp.building = loc.address
WHERE loc.builder = 12345
GROUP BY loc.builder;

-- 5.	What is the average score for all inspections performed by Inspector 102?
SELECT inspector_id, AVG(insp_score)
FROM Inspections
WHERE inspector_id = 102
GROUP BY inspector_id;
-- 6.	How much revenue did FODB receive for inspections during October? (means Oct 2021 in this case)
SELECT SUM(insp_cost)
FROM Inspections
WHERE MONTH(inspection_date) = 10;

-- 7.	How much revenue was generated this year by inspectors with more than 15 years seniority?
SELECT ispn.inspector_id,  SUM(insp_cost)
FROM Inspections as ispn
JOIN Inspectors AS ispr ON ispr.inspector_id = ispn.inspector_id
WHERE (2021 - YEAR(ispr.hire_date)) > 15
GROUP BY ispn.inspector_id;

-- 8.Demonstrate the adding of a new 1600 sq ft residential building for builder #34567 located at 1420 Main St., Lewisville TX.
    INSERT INTO locations (address, builder, type, size)
        VALUE ('1420 Main St., Lewisville, TX', 34567, 'residential', 1600);

-- 9.Demonstrate the adding of an inspection on the building you just added.
--   This framing inspection occurred on 11/21/2023 by inspector 104, with a score of 50, and note of “work not finished.”
    INSERT INTO inspections(inspection_date, inspector_id, building, type, insp_score, insp_notes)
        VALUE ('2023-11-21', 104, '1420 Main St., Lewisville, TX', 'FRM' ,50, 'work not finished');

-- 10.Demonstrate changing the cost of an ELE inspection changed to $150 effective today.
#     TESTING updating inspection cost for future inspections.
#     INSERT INTO inspections (inspection_date, inspector_id, building, type, insp_score, insp_notes)
#     VALUE ('2023-12-31', 105, '1420 Main St., Lewisville, TX', 'ELE', 90, 'TEST: SHOULD SEE PRICE UPDATE TO 150');

    UPDATE Inspection_Types
    SET cost = 150, eff_date = '2023-12-05'
    WHERE code = 'ELE';

#  REMOVING TEST DATA
#     DELETE FROM Inspections
#     WHERE inspection_id = 59;

-- 11.Demonstrate adding of an inspection on the building you just added.
--    This electrical inspection occurred on 11/22/2023 by inspector 104, with a score of 60, and note of “lights not completed.”
INSERT INTO inspections(inspection_date, inspector_id, building, type, insp_score, insp_notes)
        VALUE ('2023-11-22', 104, '1420 Main St., Lewisville, TX', 'ELE' ,60, 'lights not completed.');
-- 12.Demonstrate changing the message of the FRM inspection on 11/21/2023 by inspector #105 to “all work completed per checklist.”
UPDATE Inspections
SET insp_notes = 'all work completed per checklist'
WHERE inspection_id = 58;
-- 13.Demonstrate the adding of a POL inspection by inspector #103 on 11/28/2023 on the first building associated with builder 45678.
# this is 100 Winding Wood, Carrollton, TX; Score not specified nor are notes, so set to 100 and added my own note.
INSERT INTO inspections(inspection_date, inspector_id, building, type, insp_score, insp_notes)
        VALUE ('2023-11-28', 103, '100 Winding Wood, Carrollton, TX', 'POL' ,100, 'Pool completed per spec.');