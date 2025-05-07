abstract component  implements="IndexData" {
	
	public Query function getData() {
		if(!structKeyExists(variables,"data")) {
			variables.data=loadData();
		}
		return variables.data;
	}

	public String function getName() {
		return getType();
	}

	
	public String function getHash() {
		if(!structKeyExists(variables,"hash")) {
			local.hash=server.system.properties["lucee.#getType()#.hash"]?:"";
			if(isEmpty(local.hash)) {
				variables.data=loadData();
				local.hash=hash(variables.data.toString(),"quick");
				System::setProperty("lucee.#getType()#.hash",local.hash);
			}
			variables.hash=local.hash;
		}
		return variables.hash;
	}

	public abstract Query function loadData();
	public abstract String function getType();
}

