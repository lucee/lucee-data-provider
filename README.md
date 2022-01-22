# Home Of Lucee Download Web Application and its RESTful Service Dependencies

This repository contains the web application and the RESTful service dependencies that provide the main distribution files, such as installers, snapshots, servlet containers, beta, extensions and more.

The repository mainly consists of the following directories:

- **/download**: for hosting [http://stable.lucee.org/](http://stable.lucee.org/) and [https://downloads.lucee.org](https://downloads.lucee.org)
- **/update**: serves the update provider as RESTful service hosted at [http://update.lucee.org](http://update.lucee.org)
- **/extension**: serves the extension provider as RESTful service hosted at [http://extension.lucee.org](http://extension.lucee.org)

## Installation for local development

This documentation shows one quick example how to setup and run this repository locally, including the setup of the RESTful services to be served locally at [http://localhost:8888/rest/](http://localhost:8888/rest/) with Lucee Express for development.  

**1. Step:** Download a **Lucee Express Release** version at [https://download.lucee.org](https://download.lucee.org) and unpack it, run and see if it's serving content at [http://localhost:8888](http://localhost:8888). For more information about downloading and running **Lucee Express (ZIP)** please visit [https://docs.lucee.org/guides/installing-lucee/download-and-install.html](https://docs.lucee.org/guides/installing-lucee/download-and-install.html).

**2. Step:** Create a local directory to serve as development workspace. We will use e.g. `C:\workspace-lucee-data-provider\`.

**3. Step:** Go to the Github repository site at [https://github.com/lucee/lucee-data-provider](https://github.com/lucee/lucee-data-provider) and download the master branch by clicking the **Code**-button and **Download ZIP**. Unpack it to your workspace from 2.Step at `C:\workspace-lucee-data-provider\`, so that the content of the downloaded and unpacked repository will be located at `C:\workspace-lucee-data-provider\lucee-data-provider-master\`.

**4. Step:** Configure **"Lucee Express"** by creating a file named *ROOT.xml* at `C:\path-to-your-lucee-express\conf\Catalina\localhost\ROOT.xml`, containing the docBase attribute pointing to your local repository of your workspace as follows:

```xml
<?xml version='1.0' encoding='utf-8'?>
<Context docBase="C:\workspace-lucee-data-provider\lucee-data-provider-master\">
  <WatchedResource>WEB-INF/web.xml</WatchedResource>
  <JarScanner scanClassPath="false" />
</Context>
```

After saving the file to `C:\path-to-your-lucee-express\conf\Catalina\localhost\ROOT.xml` restart **Lucee Express**.

**5. Step:** The **lucee-data-provider** requires distribution files to be read and create content dynamically. Thus, you need to download at least one distribution file (e.g. lucee.jar) manually of each category "Release", "RC", "Snapshot", "Beta" from [https://download.lucee.org](https://download.lucee.org) to a local directory (we will use e.g. `C:\lucee-downloads\`). The same dynamic content creation applies to Lucee **Extension** distribution files. Download some *Extension* to `C:\lucee-downloads\` also, just to provide content.

**6. Step:** Next step is to feed the web application with the correct configuration values to serve the content from your local development machine (e.g. using the RESTful service of your localhost instead of the Lucees online distribution and RESTful services sites). This can be easily done within *Lucee Express* by setting **environment variables**. These will override the default settings to setup a local development context. The **environment variables** can be set as follows:

For **Lucee Express** in *Windows*, create a file named *setenv.bat*  with the following content:

```
REM #### TOMCAT WINDOWS: SETS ENV VARS in setenv.bat with the following enviroment varibales.
REM #### This won't work when running Tomcat as service. In this case you can alternatively add the 
REM #### Environment Variables by running the following Tomcat service update command in a terminal window: 
REM #### path-to-lucee-installation\tomcat\bin\tomcat9.exe //US//NameOfYourTomcatService --Environment=key1=value1;key2=...

REM S3Root need to point to a directory containing distribution files
set "LUCEE_DATA_PROVIDER_S3ROOT=C:\lucee-downloads\"
set "LUCEE_DATA_PROVIDER_UPDATE_PROVIDER_BASEURL=http://localhost:8888/rest/update/provider/"
set "LUCEE_DATA_PROVIDER_UPDATE_PROVIDER=http://localhost:8888/rest/update/provider/list?extended=true"
set "LUCEE_DATA_PROVIDER_EXTENSION_PROVIDER=http://localhost:8888/rest/extension/provider/info?withLogo=true&type=all"
set "LUCEE_DATA_PROVIDER_EXTENSION_DOWNLOAD=http://localhost:8888/rest/extension/provider/{type}/{id}"
set "LUCEE_DATA_PROVIDER_EXTENSION_PROVIDER_RELEASE=http://localhost:8888/rest/extension/provider/info?withLogo=true&type=release"
set "LUCEE_DATA_PROVIDER_EXTENSION_PROVIDER_ABC=http://localhost:8888/rest/extension/provider/info?withLogo=true&type=abc"
set "LUCEE_DATA_PROVIDER_EXTENSION_PROVIDER_SNAPSHOT=http://localhost:8888/rest/extension/provider/info?withLogo=true&type=snapshot"

REM set "LUCEE_DATA_PROVIDER_S3URL=https://s3-eu-west-1.amazonaws.com/lucee-downloads/"

REM exit from setenv.bat
exit /b 0

```

Save that file to `C:\path-to-your-lucee-express\bin\setenv.bat` and restart **Lucee Express**.

For **Lucee Express** in *Linux*, create a file named *setenv.sh*  with the following content:

```

# TOMCAT LINUX: SETS ENV VARS in setenv.sh with the following enviroment varibales:

# S3Root pointing to distribution files
LUCEE_DATA_PROVIDER_S3ROOT=\var\www\lucee-downloads\
LUCEE_DATA_PROVIDER_UPDATE_PROVIDER_BASEURL=http://localhost:8888/rest/update/provider/
LUCEE_DATA_PROVIDER_UPDATE_PROVIDER=http://localhost:8888//rest/update/provider/list?extended=true
LUCEE_DATA_PROVIDER_EXTENSION_PROVIDER=http://localhost:8888/rest/extension/provider/info?withLogo=true&type=all
LUCEE_DATA_PROVIDER_EXTENSION_DOWNLOAD=http://localhost:8888/rest/extension/provider/{type}/{id}
LUCEE_DATA_PROVIDER_EXTENSION_PROVIDER_RELEASE=http://localhost:8888/rest/extension/provider/info?withLogo=true&type=release
LUCEE_DATA_PROVIDER_EXTENSION_PROVIDER_ABC=http://localhost:8888/rest/extension/provider/info?withLogo=true&type=abc
LUCEE_DATA_PROVIDER_EXTENSION_PROVIDER_SNAPSHOT=http://localhost:8888/rest/extension/provider/info?withLogo=true&type=snapshot

#LUCEE_DATA_PROVIDER_S3URL=https://s3-eu-west-1.amazonaws.com/lucee-downloads/

```

Save that file to `\path-to-your-lucee-express\bin\setenv.sh` and restart **Lucee Express**. This file may need execution permission to run on Linux.

Of course, the environment variables can be set in many other ways, e.g. from within your OS (as an alternative to setenv.bat/setenv.sh)

**7. Step:** Set up and add the RestFull Services by running the *updateRestMappings.cfm* template located at [http://localhost:8888/download/updateRestMappings.cfm](http://localhost:8888/download/updateRestMappings.cfm). This template is physically loacted at `/download/updateRestMappings.cfm` and contains the [restInitApplication() function](https://docs.lucee.org/reference/functions/restinitapplication.html) to add RESTful mappings to serve restpaths "extension" and "update" restpaths to your localhost context. Note that you MUST provide your Lucee Web Administration password to run restInitApplication().

To make sure the RESTful mappings are correclty being served, log into your *Lucee Web Administrator* -&gt; *Archives & Resources* -&gt; *Rest*, and activate *"List services"*. Then navigate to [http://localhost:8888/rest/](http://localhost:8888/rest/) to see them listed.

**8. Step:** Open the **download web application** at  [http://localhost:8888/download/](http://localhost:8888/download/)

**IMPORTANT NOTE**: 

- When working with this repository locally, some changes made to the components serving RESTful services (e.g. UpdateProvider.cfc or ExtensionProvider.cfc ) may need to have the mappings updated for the changes to take effect. For this purpose simply run the [updateRestMappings.cfm](https://github.com/andreasRu/lucee-data-provider/blob/patch-andreasru/download/updateRestMappings.cfm) by calling it at [http://localhost:8888/download/updateRestMappings.cfm](http://localhost:8888/download/updateRestMappings.cfm).

- To update/refresh/reset the download site, run [http://localhost:8888/download/?reset](http://localhost:8888/download/?reset).
