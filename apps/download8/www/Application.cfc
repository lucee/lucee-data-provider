component {
	this.name = "lucee-downloads";

	this.componentPaths = [
      {
         "physical": "/var/components/",
         "archive": "",
         "primary": "physical"
      }
   ];

	function onApplicationStart() {
		application.util = new org.lucee.download.Util();
	}

	function onRequestStart() {
		if (!structKeyExists(application, "util")) onApplicationStart();
	}
}
