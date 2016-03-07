<cfscript>
	http url="https://oss.sonatype.org/content/repositories/snapshots/org/lucee/lucee/5.0.0.80-SNAPSHOT/maven-metadata.xml" 
	result="content" {
		httpparam type="header" name="accept" value="application/json";
	}
	dump(content);
</cfscript>
