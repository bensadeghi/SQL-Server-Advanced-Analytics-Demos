---------------------------------------------------------
-- Simple demo of SQL Server 2017 Python (ML) Services --
-- Uses the SciKit-Learn model on the Iris dataset ------
---------------------------------------------------------

-- first, enable external script services --
-- https://docs.microsoft.com/en-us/sql/advanced-analytics/r/set-up-sql-server-r-services-in-database#a-namebkmkenablefeaturea-step-2-enable-external-script-services

-- Hello World print out example --
execute sp_execute_external_script 
@language = N'Python',
@script = N'print("HELLO WORLD !!!")'
GO

-- create a simple table and populate it --
DROP TABLE IF EXISTS MyTableData;
CREATE TABLE MyTableData([Col1] INT NOT NULL) ON [PRIMARY];
INSERT INTO MyTableData VALUES(1);
INSERT INTO MyTableData VALUES(10);
INSERT INTO MyTableData VALUES(100);
GO
-- print all rows of MyTableData --
SELECT * FROM MyTableData;


-- pass select query results to Python and multiply by 9 --
EXEC sp_execute_external_script
@language = N'Python',
@script = N'OutputDataSet = InputDataSet * 9',
@input_data_1 = N'SELECT * FROM MyTableData;'
WITH RESULT SETS (([NewColName] INT NOT NULL));

-- matrix multiplication with Python (outer product) --
EXEC sp_execute_external_script
@language = N'Python',
@script = N'
import numpy
x = InputDataSet
y = range(12,16)
OutputDataSet = pandas.DataFrame(numpy.outer(x, y))',
@input_data_1 = N'SELECT * FROM MyTableData;'
WITH RESULT SETS ((Col1 INT, Col2 INT, Col3 INT, Col4 INT));

-- fetch iris dataset from sklearn package --
DROP PROC IF EXISTS get_iris_dataset;  
GO
CREATE PROC get_iris_dataset AS BEGIN
EXEC sp_execute_external_script
@language = N'Python',
@script = N'
from sklearn import datasets
iris = datasets.load_iris()
OutputDataSet = pandas.DataFrame(iris.data)
mapping = {0:"setosa", 1:"versicolor", 2:"virginica"}
labels = pandas.DataFrame(iris.target).replace(mapping)
OutputDataSet["Species"] = labels'
WITH RESULT SETS ((
	"Sepal.Length" FLOAT NOT NULL,   
	"Sepal.Width" FLOAT NOT NULL,  
	"Petal.Length" FLOAT NOT NULL,   
	"Petal.Width" FLOAT NOT NULL, 
	"Species" VARCHAR(100) NOT NULL));  
END;
GO

DROP TABLE IF EXISTS iris_data
GO
CREATE TABLE iris_data ( 
  "Sepal.Length" FLOAT NOT NULL, 
  "Sepal.Width" FLOAT NOT NULL, 
  "Petal.Length" FLOAT NOT NULL, 
  "Petal.Width" FLOAT NOT NULL, 
  "Species" VARCHAR(100) NOT NULL);
GO 
INSERT INTO iris_data EXEC get_iris_dataset;
GO
-- print all rows of iris_data --
SELECT * FROM iris_data;
GO

-- generate a Sklearn decision tree model using data from SQL Server table --
DROP PROC IF EXISTS generate_iris_model;
GO
CREATE PROC generate_iris_model (@trained_model varbinary(max) OUTPUT) AS BEGIN
EXEC sp_execute_external_script  
@language = N'Python',
@script = N'
from sklearn import tree
import pickle

features = InputDataSet[["Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width"]]
labels   = InputDataSet[["Species"]]

clf = tree.DecisionTreeClassifier()
iris_model = clf.fit(features, labels)
trained_model = pickle.dumps(iris_model)',

@input_data_1 = N'SELECT * FROM iris_data',
@params = N'@trained_model varbinary(max) OUTPUT',
@trained_model = @trained_model OUTPUT;
END;
GO


-- create SQL Server table to store model --
DROP TABLE IF EXISTS built_models;
CREATE TABLE built_models (
	model_name VARCHAR(30) NOT NULL DEFAULT('default model') PRIMARY KEY,
	model varbinary(max) NOT NULL
);
GO

-- save Python model object in SQL Server table --
DECLARE @model VARBINARY(MAX);
EXEC generate_iris_model @model OUTPUT;
INSERT INTO built_models (model_name, model) VALUES('DTree', @model);

SELECT * FROM built_models;
GO

-- make predictions using the decision tree model --
DROP PROCEDURE IF EXISTS predict_species;
GO
CREATE PROCEDURE predict_species (@model VARCHAR(100)) AS BEGIN
DECLARE @dtree_model varbinary(max) = (SELECT model FROM built_models WHERE model_name = @model);
EXEC sp_execute_external_script
@language = N'Python',
@script = N'
import pickle

model = pickle.loads(dtree_model)

features = InputDataSet[["Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width"]]
probArray = model.predict_proba(features)
OutputDataSet = pandas.DataFrame(probArray)',

@input_data_1 = N'SELECT * FROM iris_data',
@params = N'@dtree_model varbinary(max)',
@dtree_model = @dtree_model
WITH RESULT SETS (("Setosa_Prob" FLOAT, "Versicolor_Prob" FLOAT, "Virginica_Prob" FLOAT));
END;
GO
EXEC predict_species 'DTree';
GO
