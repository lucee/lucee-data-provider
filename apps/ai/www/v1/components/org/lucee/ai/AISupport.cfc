component {
	NL="
";
	variables.totalConsumption={};
	/**
	 * general invoke method called for all requests
	 * @endpoint 
	 * @version 
	 */
	public function invoke(endpoint, version) {
		try {
			if("chat/completions"==arguments.endpoint) {
				chatCompletions();
			}
			else if("models"==arguments.endpoint) {
				models();
			}
			else {
				cfthrow(
					message: "Endpoint [#arguments.endpoint#] is not supported in API version [#version#].",
					errorcode: "unsupported_endpoint",
					type: "invalid_request_error"
				);
			}
		}
		catch(ex) {
			systemOutput(ex,1,1);
			handleException(ex);
			return;
		}
	}

	/**
	 * create data to create a session
	 * @data 
	 */
	private static function createSessionData(data) {
		var sct= {
			"temperature": static.temperature,
			"limit": static.limit,
			"connectionTimeout": static.connectionTimeout,
			"socketTimeout": static.socketTimeout,
			"history": []
		};

		var entry=[:];
		loop array=data.messages item="local.msg" {
			if(msg.role=="system") sct["systemMessage"]=msg.content;
			else if(msg.role=="user") entry["question"]=msg.content;
			else if(msg.role=="assistant") {
				entry["answer"]=msg.content;
				arrayAppend(sct.history,entry);
				var entry=[:];
			}
			else {
				cfthrow(
					message: "invalid message role [#msg.role#], valid roles are [assistant, user, system].",
					type: "invalid_request_error"
				);
			}
		}
		if(!structKeyExists(sct,"systemMessage") || isEmpty(sct.systemMessage)) {
			sct["systemMessage"]=static.systemMessage;
		}
		// TODO check for existence and handle if not
		sct["inquiry"]=entry.question;
		return sct;
	
	}

	/**
	 * read input send by data
	 * @method allowed method to write from
	 */
	package static function readInput(method, boolean validate=false) {
		var data=getHTTPRequestData();
		if(method!=data.method) {
			cfthrow(
				message: "Method #ucase(data.method)# not allowed. This endpoint only supports #method# requests.",
				errorcode: "method_not_allowed"
				type:"invalid_request_error"
			);
		}
		var auth=trim(data.headers.authorization?:"");
		if(left(auth,7)=="Bearer ") {
			auth=trim(mid(auth,8));
		}

		var rtn={"auth":auth};
		if(structKeyExists(data,"content") && !isEmpty(data.content)) {
			rtn["raw"]=trim(data.content);
			rtn["data"]=deserializeJSON(data.content);
		}
		else {
			validate=false;
		}
		return rtn;
	}

	package function validate(input) {
		// full access with no limitation 
		if(input.auth==application.fullAccessSecretKey) {
			return;
		}
		var minuteKey=FormatBaseN(int(getTickCount("s")/60),36);
		if(structKeyExists(application,"lastMinuteKey") && (application.lastMinuteKey?:minuteKey)!=minuteKey) {
			structDelete(variables.totalConsumption,application.lastMinuteKey?:"undefined",false);
		}
		application.lastMinuteKey=minuteKey;
		var consumption=variables.totalConsumption[minuteKey]?:0;
		var upcomingConsumption=len(input.raw);
		if(application.allowedMinuteConsumption<(consumption+upcomingConsumption)) {
			cfthrow(
				message: "Rate limit exceeded. Maximum request size per minute reached. Please try again after one minute.",
				errorcode: "rate_limit_exceeded",
				type: "request_limit_error"
			);
		}
		variables.totalConsumption[minuteKey]=consumption+upcomingConsumption;
	}

	/**
	 * writes out data to response stream
	 * @data  data to write out
	 */
	package static function writeOut(data) {
		setting show=false;
		content type="application/json;charset=UTF-8";
		
		echo(serializeJSON(data));
	}

	/**
	 * writes an exception to the response stream in the proper format
	 * @ex exception to write  
	 */
	package static function handleException(ex) {
		if(structKeyExists(ex,"errorcode")) local.code=ex.errorcode;
		else if(structKeyExists(ex,"code")) local.code=ex.code;
		
		writeOut({
			"error": [
				"message": ex.message,
				"type": ex.type ?: "server_error",
				"code": local.code ?: nullValue()
			]
		});
	}
}