component {
	this.name = "lucee-downloads";
	variables.maxAge=60*60; // 1 hour
	// variables.maxAge=10; // 10 seconds
	this.componentMappings = [
      {
         "physical": "/var/components/",
         "archive": "",
         "primary": "physical"
      }
   ];

	function onRequestStart() {
		if(isNull(application.util ) || !isNull(url.flush) ) {
			application.util = new org.lucee.download.Util();
		}
	}

	function onRequest(template) {
		var filename=application.util.getCacheFile(arguments.template);
		cache timeSpan=createTimespan(0,0,0,maxAge) useQueryString=true {
			if(fileExists(filename)) {
				echo(fileRead(filename));
				var expired=getTickCount()>(fileInfo(filename).dateLastModified.getTime()+((variables.maxAge-1)*1000));
				if(expired) {
					lock name="cache-#filename#" type="exclusive" timeout="0" throwOnTimeout=false {
						thread action="run" name="cache-regen-#filename#-#getTickCount()#" template=template filename=filename {
							load(attributes.template, attributes.filename);
						}
					}
				}
			} 
			else {
				echo(load(arguments.template,filename));	
			}
		}
	}

	private function load(template,filename) {
		saveContent variable="local.content" {
			include template;
			echo("<!-- cached at #now()# -->");
		}
		fileWrite(filename,local.content);
		return local.content;
	}
}
