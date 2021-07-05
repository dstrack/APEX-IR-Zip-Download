# APEX-IR-Zip-Download
pl/sql code for downloading of large APEX Interactive Reports as ZIP files.
In case you have to download very large reports from an APEX Instance that is running behind a web proxy server or in cases where you have to download reports with more rows than the technical limit allows you to use, you can use the method to successfully download these reports. The Sample App can be installed in an APEX 5 (or higher) Workspace.


Usage:
1. Install the package IR_Zip_Download in your application schema.
2. add a Button to your Report region.
3. set 'Reload on Submit' to 'Allways' in APEX 18 and higher.
4. add a 'Branch' of type 'PL/SQL Procedure' or 'Process' of type 'PL/SQL Code' with the following code:

IR_Zip_Download.Download_Zip(
    p_Region_Name => 'Sample Report', /* Enter your IR region title here */
    p_Application_ID => :APP_ID,
    p_App_Page_ID => :APP_PAGE_ID
);

The procedure performs the following steps:
1. Extract the query with APEX_IR.GET_REPORT
2. Bind the variables for filter conditions
3. Open cursor for query and load the rows
4. Convert to CSV. The parameters 'CSV Separator', 'CSV Enclosed By', and 'Filename' defined under Attributes / Download of the report region are recognized. The Enclosing character is only used, when a data value contains the 'CSV Separator', or newline character.
6. Convert to ZIP with APEX_ZIP.ADD_FILE. Up to 2GB of compressed data can be processed.
7. Start the download to the browser
