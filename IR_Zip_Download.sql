/*
Copyright 2019 Dirk Strack, Strack Software Development

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

declare 
	v_has_Reload_on_Submit VARCHAR2(128);
	v_stat VARCHAR2(32767);
begin 
	SELECT case when TO_NUMBER(SUBSTR(VERSION_NO, 1, INSTR(VERSION_NO, '.') - 1)) >= 18 
		then 'TRUE' else 'FALSE' end 
	INTO v_has_Reload_on_Submit
	FROM APEX_RELEASE;
	
	v_stat := '
CREATE OR REPLACE PACKAGE IR_Zip_Download 
AUTHID DEFINER
IS
	g_has_Reload_on_Submit CONSTANT BOOLEAN := ' || v_has_Reload_on_Submit || q'[;
	PROCEDURE  Download_Zip (
		p_Region_Name 	IN VARCHAR2,
		p_Application_ID IN NUMBER DEFAULT NV('APP_ID'),
		p_App_Page_ID 	IN NUMBER DEFAULT NV('APP_PAGE_ID')
	);

	FUNCTION Process_Download_Zip (
		p_process in apex_plugin.t_process,
		p_plugin  in apex_plugin.t_plugin )
	RETURN apex_plugin.t_process_exec_result;
END;
]';
	EXECUTE IMMEDIATE v_Stat;
end;
/



create or replace package body IR_Zip_Download 
as
    c_App_Error_Code        CONSTANT INTEGER := -20200;
    c_msg_no_data_found 	CONSTANT VARCHAR2(500) := 'The query does not deliver any rows. No data found.'; 
	c_msg_region_not_found	CONSTANT VARCHAR2(500) := 'The region name could not be found on the current page.';
	c_msg_bad_setting 		CONSTANT VARCHAR2(500) := q'[Set Apex page property 'Reload on Submit' to 'always' to enable this download]';

	FUNCTION cursor_to_csv (
		p_cursor_id     INTEGER,
		p_Separator IN VARCHAR2 DEFAULT ';',
		p_Enclosed_By IN VARCHAR2 DEFAULT '"'
	)
	RETURN CLOB
	IS
		l_colval        VARCHAR2 (2096);
		l_buffer        VARCHAR2 (32767) DEFAULT '';
		i_colcount      NUMBER DEFAULT 0;
		l_separator     VARCHAR2 (10);
		l_enclosed_by   VARCHAR2 (10);
		l_file          CLOB;
		l_eol           VARCHAR(2) DEFAULT CHR (10);
		l_colsdescr     dbms_sql.desc_tab;
	BEGIN
		l_separator := NVL(p_Separator, ';');
		l_enclosed_by := NVL(p_Enclosed_By, '"');
		dbms_sql.describe_columns(p_cursor_id, i_colcount, l_colsdescr);
		FOR i IN 1 .. i_colcount
		LOOP
			dbms_sql.define_column (p_cursor_id, i, l_colval, 2000);
			l_buffer := l_buffer || case when i > 1 then l_separator end || l_colsdescr(i).col_name;
		END LOOP;
		dbms_lob.createtemporary(l_file, true, dbms_lob.call);
		l_buffer := l_buffer || l_eol;
		dbms_lob.write( l_file, LENGTH(l_buffer), 1, l_buffer);
		LOOP
			EXIT WHEN dbms_sql.fetch_rows (p_cursor_id) <= 0;
			l_buffer := '';
			FOR i IN 1 .. i_colcount
			LOOP
				dbms_sql.column_value (p_cursor_id, i, l_colval);
				IF (INSTR(l_colval, l_separator) > 0 or INSTR(l_colval, l_eol) > 0)
				THEN
					l_colval := l_enclosed_by || REPLACE(l_colval, l_enclosed_by, l_enclosed_by||l_enclosed_by) || l_enclosed_by;
				END IF;
				l_buffer := l_buffer || case when i > 1 then l_separator end || l_colval;
			END LOOP;
			l_buffer := l_buffer || l_eol;
			dbms_lob.writeappend( l_file, LENGTH(l_buffer), l_buffer);
		END LOOP;
		RETURN l_file;
	END cursor_to_csv;

	FUNCTION Report_to_CSV (
		p_report IN  apex_ir.t_report,
		p_Separator IN VARCHAR2 DEFAULT ';',
		p_Enclosed_By IN VARCHAR2 DEFAULT '"'
	)
	RETURN CLOB
	IS
		v_ret 		INTEGER;
		v_curid 	INTEGER;
		v_file      CLOB;
	BEGIN
		if p_report.sql_query IS NOT NULL then 
			v_curid := dbms_sql.open_cursor;
			dbms_sql.parse(v_curid, apex_plugin_util.replace_substitutions (p_report.sql_query), DBMS_SQL.NATIVE);
			for i in 1..p_report.binds.count
			loop
				dbms_sql.bind_variable(v_curid, p_report.binds(i).name, p_report.binds(i).value);
			end loop;
			v_ret := DBMS_SQL.EXECUTE(v_curid);
			v_file := cursor_to_csv (v_curid, p_Separator, p_Enclosed_By);
			dbms_sql.close_cursor (v_curid);
		end if;
		return v_file;
	EXCEPTION
		WHEN OTHERS THEN
			dbms_output.put_line(SQLERRM);

			IF dbms_sql.is_open (v_curid) THEN
				dbms_sql.close_cursor (v_curid);
			END IF;
			RAISE;
	END Report_to_CSV;

    FUNCTION Clob_To_Blob(
        p_src_clob IN CLOB,
		p_charset IN VARCHAR2 DEFAULT 'AL32UTF8' -- 'WE8ISO8859P1'
    ) RETURN BLOB
    IS
        v_dstoff	    pls_integer := 1;
        v_srcoff		pls_integer := 1;
        v_langctx 		pls_integer := dbms_lob.default_lang_ctx;
        v_warning 		pls_integer := 1;
    	v_blob_csid     pls_integer := nls_charset_id(p_charset);
    	v_dest_lob		BLOB;
    BEGIN
    	dbms_lob.createtemporary(v_dest_lob, true, dbms_lob.call);
        dbms_lob.converttoblob(
            dest_lob     =>	v_dest_lob,
            src_clob     =>	p_src_clob,
            amount	     =>	dbms_lob.getlength(p_src_clob),
            dest_offset  =>	v_dstoff,
            src_offset	 =>	v_srcoff,
            blob_csid	 =>	v_blob_csid,
            lang_context => v_langctx,
            warning		 => v_warning
        );
        return v_dest_lob;
    END Clob_To_Blob;

	PROCEDURE  Download_Zip (
		p_Region_Name 	IN VARCHAR2,
		p_Application_ID IN NUMBER DEFAULT NV('APP_ID'),
		p_App_Page_ID 	IN NUMBER DEFAULT NV('APP_PAGE_ID')
	)
	IS
		v_csv 			CLOB;
		v_file_content 	BLOB;
		v_region_id 	APEX_APPLICATION_PAGE_IR.REGION_ID%TYPE;
		v_report 		apex_ir.t_report; 
		v_reload_on_submit_code VARCHAR2(16);
		v_zip_file 		BLOB;
		v_File_Name		varchar2(1024);
		v_File_Size  	pls_integer;
		v_Separator 	VARCHAR2(16);
		v_Enclosed_By	VARCHAR2(16);
	BEGIN
		begin 
			select REGION_ID, FILENAME, SEPARATOR, ENCLOSED_BY
			into v_region_id, v_File_Name, v_Separator, v_Enclosed_By
			from APEX_APPLICATION_PAGE_IR
			where APPLICATION_ID = p_Application_ID
			and PAGE_ID = p_App_Page_ID
			and REGION_NAME = p_Region_Name;
		exception when NO_DATA_FOUND then
			raise_application_error (c_App_Error_Code, c_msg_region_not_found);
		end;
$IF IR_Zip_Download.g_has_Reload_on_Submit $THEN 
		select RELOAD_ON_SUBMIT_CODE
		into v_reload_on_submit_code
  		from APEX_APPLICATION_PAGES
 		where APPLICATION_ID = p_Application_ID
		and PAGE_ID = p_App_Page_ID;
		if v_reload_on_submit_code != 'A' then 
			raise_application_error (c_App_Error_Code, c_msg_bad_setting);
		end if;
$END	
		v_report := APEX_IR.GET_REPORT (
			p_page_id => p_App_Page_ID,
			p_region_id => v_region_id, 
			p_report_id => null);
		if apex_application.g_debug then
			apex_debug.message(
				p_message =>  'Download_IR_as_Zip.Download_Zip(p_Region_Name => %s, Query => %s)',
				p0 => DBMS_ASSERT.ENQUOTE_LITERAL(p_Region_Name),
				p1 => v_report.sql_query,
				p_max_length => 3500
			);
		end if;
		v_File_Name := NVL(apex_plugin_util.replace_substitutions (v_File_Name), p_Region_Name || '.csv');
		v_Separator := apex_plugin_util.replace_substitutions (v_Separator);
		v_Enclosed_By := apex_plugin_util.replace_substitutions (v_Enclosed_By);
		v_csv := IR_Zip_Download.Report_to_CSV(v_report, v_Separator, v_Enclosed_By);
		if dbms_lob.getlength(v_csv) > 0 then
			v_file_content := IR_Zip_Download.Clob_To_Blob (
				p_src_clob	=> v_csv
			);
			apex_zip.add_file (
				p_zipped_blob => v_zip_file, 
				p_file_name => v_File_Name , 
				p_content => v_file_content );
			apex_zip.finish (
				p_zipped_blob => v_zip_file );
		
			v_File_Size := dbms_lob.getlength(v_zip_file);
			v_File_Name := p_Region_Name || '.zip';
			if apex_application.g_debug then
				apex_debug.message(
					p_message =>  'Download_IR_as_Zip.Download_Zip(v_File_Name => %s, v_File_Size => %s)',
					p0 => DBMS_ASSERT.ENQUOTE_LITERAL(v_File_Name),
					p1 => v_File_Size,
					p_max_length => 3500
				);
			end if;
			htp.init();
			owa_util.mime_header('application/zip', false);
			htp.p('Content-length: ' || v_File_Size);
    		htp.p('Content-Disposition: attachment; filename=' || dbms_assert.enquote_name(v_File_Name, false) );
			owa_util.http_header_close;
			wpg_docload.download_file( v_zip_file );
			apex_application.stop_apex_engine;
		else 
			raise_application_error (c_App_Error_Code, c_msg_no_data_found);
		end if;
	END Download_Zip;

	FUNCTION Process_Download_Zip (
		p_process in apex_plugin.t_process,
		p_plugin  in apex_plugin.t_plugin )
	RETURN apex_plugin.t_process_exec_result
	IS
		v_exec_result apex_plugin.t_process_exec_result;
		v_Region_Name VARCHAR2(32767) := p_process.attribute_01;
    BEGIN
        if apex_application.g_debug then
            apex_debug.info('IR Region Name : %s', v_Region_Name);
        end if;
		IR_Zip_Download.Download_Zip(
			p_Region_Name => v_Region_Name
		);
		RETURN v_exec_result;
	END Process_Download_Zip;

end IR_Zip_Download;
/
show errors

