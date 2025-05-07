component extends="org.lucee.ai.AISupport" {

	import org.lucee.ai.proxy.*;
	import org.lucee.ai.rag.*;

	static {
		static.models=[
			{
				"id":"main",
				"description":"this is the main model"
			}
		];

		static.temperature=0.7;
		static.limit=50;
		static.connectionTimeout=3000;
		static.socketTimeout=10000;
		
		NL="
		";

		static.systemMessage="You are a Lucee expert and documentation guide. "
						&"Users will ask questions about Lucee functions, tags, or configurations running Lucee version #server.lucee.version#. "
						&"Some queries will include relevant documentation context while others may not have matching documentation. "
						&"When documentation context is provided, it will be an array of documents, each containing: "&NL
						&"- A 'title' field containing the document title "&NL
						&"- A 'summary' field with a brief overview "&NL
						&"- A 'keywords' field listing relevant terms "&NL
						&"- A 'content' field containing the documentation text in markdown format in pieces as an array, every element contains the folowing pieces"&NL
						&"   - start - start position in the original text"&NL
						&"   - end - end position in the original text"&NL
						&"   - score - score  score from Lucene for that piece"&NL
						&"   - data - the content piece itself"&NL
						&"- A 'source' field with the documentation URL "&NL
						&"- A 'score' field indicating the relevance to the query "&NL
						&"- A 'rank' field indicating the position in search results "&NL&NL
						&"Documents are ordered by relevance, with the most relevant first. "
						&"When documentation context is provided, base your response primarily on that information and include the source URLs for reference. "
						&"When no context is provided, respond based on your general knowledge of Lucee. "
						&"Respond concisely in plain HTML, without using triple backticks. "
						&"Biggest heading tag you can use is h2. "
						&"Start every answer with a h2 tag containg a title for your answer."
						&"Regular text in a p tag."
						&"For multi-line code examples, use <code class=""lucee-ml"">. "
						&"For inline code, use <code>. Avoid <code> within heading tags, and ensure all code is properly escaped with &lt;. "
						&"Structure responses clearly and briefly for direct HTML integration. "
						&"When responding: "&NL
						&"1. Use provided documentation context when available "&NL
						&"2. Include source URLs when referencing specific documentation "&NL
						&"3. Maintain consistent HTML formatting throughout your response "&NL
						&"4. if the request is nt clear, say so and do not assume to much "&NL
						&"5. whenever possible make a code example "&NL
						&"6. code examples as much as possible in cfscript code "&NL
						&"7. For queries without context, provide the best possible answer based on general Lucee expertise";



	}

	public function init() {
		systemOutput("AIProxy.init",1,1);
		variables.rag=new RAG([
			new RecipeIndexData()
			,new TagIndexData()
			,new FunctionIndexData()
		],"luceeai");
	}


	/**
	 * chat completitions endpoint
	 */
	public function chatCompletions() {
		var data=readInput("POST");
		var forwardData=createSessionData(data);
		var inquiry=forwardData.inquiry;
		structDelete(forwardData,"inquiry",false);
		var inquiry=variables.rag.augment(inquiry);
		var ai=LoadAISession("finalDestination", forwardData);
		
		// stream
		if(data.stream?:false) {
			var choices={
				"choices":[
					{
						"delta":{
							"content":"42"
						}
					}
				]
			};
			
			setting show=false;
			content type="text/event-stream";
			flush;
			inquiryAISession(ai, inquiry,function(part,  chunkIndex,  isComplete) {
				echo("data: "&serializeJSON(var:{
					"choices":[
						{
							"delta":{
								"content":part
							}
						}
					]
				},compact:true)&NL);
				flush;
			});
			echo("[DONE]"&NL);
			flush;
			return;
		}
		

		// write to reponse stream
		var rsp = inquiryAISession(ai, inquiry);
		writeOut({
			"choices":[
				{
					"message":{
						"content":rsp
					}
				}
			]
		});
	}

	/**
	 * models 
	 */
	public function models()  {
		readInput("GET");
		writeOut({
			"data":static.models
		});
	}

}