Little vibe coded tool that add a given static import to a given list of java classes.

So far I've used it in parallel changes of builders using a prompt like the following:

> use the dev/add-static-import.sh script to add an static import of 
> com.cms_comunidades.helpers.ClaimBuilderX.aClaim 
> to the following classes 
> [ClaimCommandsProcessorTest.java,
> AllClaimCommandsRepositoryTest.java,
> NotifyOpenedClaimCommandTest.java,
> ForDemoAcmeCompanyTest.java,
> CompaniesTest.java,
> EBrokerClaimsReaderTest]

