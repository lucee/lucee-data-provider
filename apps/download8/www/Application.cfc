component {
	this.name = "lucee-downloads";

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
}
