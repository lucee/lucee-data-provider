
component {

  // define the AI Lucee uses as base
  this.ai["finalDestination"]= deserializeJSON(server.system.environment.AI_ENDPOINT);
  //{'class': 'lucee.runtime.ai.anthropic.ClaudeEngine','custom': {'model': '','temperature': '0.1','apiKey': '${CLAUDE_API_KEY}','connectTimeout': "1000",'socketTimeout': '5000','conversationSizeLimit': '10'}}
  
  // map the components used
  this.componentpaths = [
    {
       "physical": getDirectoryFromPath(getCurrentTemplatePath()) &"components/",
       "archive": "",
       "primary": "physical",
       "inspectTemplate": "always"
    }
  ];




  public function onRequest(template) {
    systemOutput("---- before ------",1,1);
    systemOutput((this.ai),1,1);
    //if(!structKeyExists(application, "ai")) {
		  application.aiproxy=new org.lucee.ai.proxy.AIProxy();
    //}
    
    var endpoint=listCompact(replace(arguments.template,"/index.cfm",""),"/");
    var version=listFirst(endpoint,"/");
    var endpoint=listCompact(replace(endpoint,version,""),"/");
    
    application.aiproxy.invoke(endpoint,version);
    systemOutput("---- after.invoke ------",1,1);
  }



	systemOutput(cgi.request_url?:"",1,1);


}