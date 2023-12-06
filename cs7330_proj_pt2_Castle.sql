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
    prerequisites VARCHAR(50) DEFAULT('none'), -- revisit later
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

DROP TABLE Builders;
DROP TABLE Inspections;

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

-- Create trigger to inspect and update any inspections scheduled after a cost change


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

-- Create inspection to test trigger
INSERT INTO locations VALUE (19, '12 NO BUILDER LN, PLANO, TX', null, 'residential', null, null);
TRUNCATE Inspections;


-- Part 2 SQL Questions
-- 1.List all buildings (assume builder#, address, type) that do not have a final (FNL, FN2, FN3) inspection.
SELECT loc.builder, loc.address, MAX(ins.type) as type
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
SELECT I.inspector_id, S.inspector_name
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
GROUP BY ispn.inspector_id
