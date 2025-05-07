interface {
	/**
	 * linking the name of the columns of the query to the attributes of the tag cfindex
	 * for example: 
	 * {key="url",title="title",body="body"}
	 * means that the column "url" holds the key, the column "title" holds the title and so on
	 */
	public Struct function getColumnNames();

	
	public Query function getData();

	public String function getName();

	public String function getHash();

}