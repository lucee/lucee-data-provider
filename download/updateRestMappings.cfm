<cfscript>
    /***
    * Run this template to add/update Restful services from within your web-context (e.g. http://localhost:8888/download/updateRestMappings.cfm ) 
    * that will add/update the Rest Service. After running, confirm with http://localhost:8888/rest (to activate rest listings go
    * to: Lucee Administrator -> Archives & Resources -> Rest, and activate "List services")
    ***/

    if( cgi.SERVER_NAME=="localhost") {
        basePath=getDirectoryFromPath( getTemplatePath() );
        restInitApplication( 
            dirPath= basePath & "/../extension", 
            serviceMapping="extension", 
            password="myDevWebAdminPassword"
        );

        restInitApplication( 
            dirPath= basePath & "/../update", 
            serviceMapping="update", 
            password="myDevWebAdminPassword"
        );

        echo("REST mappings updated for localhost");
    }
    
</cfscript>