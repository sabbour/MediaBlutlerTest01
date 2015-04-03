
#Azure Subscription
$azureSubscriptionName="[your subscription name]"
#Media Butler Storage Account Name
$butlerStorageAccountName="[your butler Storage AccountName]"
#Media Servives Account Name
$MediaServiceAccountName="[your AMS account name]"
#Media Services Account Key
$PrimaryMediaServiceAccessKey="[your AMS Primary key]"
#Media Services Storage Account Connection string
$MediaStorageConn="[your Storage Account connection string]"
#Service Bus Connection string
$ServiceBusConn="[your Service Bus connection string]"
#Service Bus Topic
$ServiceBusTopic="[your Service Bus Topic name]"
#Service Bus Subscription
$ServiceBusSubscription="[your Service Bus Subscription name]"
#AlternateId config (what to put as the AlternateId). 0 = Control File name [default], 1 = json object inside control "AlternateID", 2 = Original File Name , 3 = GUID container folder
$AlternateIdConfig="2"
#[Optional] Send Grid configuration, if you don't use Sendgrig keep empty string
#Example "{ ""UserName"":""xxxxxxxxxxx@azure.com"", ""Pswd"":""xxxxxxxxxxx"", ""To"":""admin@yourdomain.com"", ""FromName"": ""Butler Media Framework"", ""FromMail"": ""butler@media.com"" }"
$SendGridStepConfig=""
#Media Butler Cloud Services Name
$serviceName="[you Cloud Service Name here]"
#Media Butler Cloud Services Location
$serviceLocation="[your Cloud Service and Media Services Region]"

#Constante, not change
#Media Butler Cloud Services Slot
$slot="Production"
#Media Butler Package URL
$package_url="http://sabbourbutlermedia.blob.core.windows.net/app/MediaButler.AllinOne.cspkg"
#Media Butler Config URL
$config_Url="https://raw.githubusercontent.com/sabbour/MediaBlutlerTest01/master/MediaButler.AllinOne/bin/Release/app.publish/ServiceConfiguration.Cloud.cscfg"


Function InsertButlerConfig($accountName,$accountKey,$tableName, $PartitionKey,$RowKey,$value   )
{
  	#Create instance of storage credentials object using account name/key
	$accountCredentials = New-Object "Microsoft.WindowsAzure.Storage.Auth.StorageCredentials" $accountName, $accountKey.Primary
	#Create instance of CloudStorageAccount object
	$storageAccount = New-Object "Microsoft.WindowsAzure.Storage.CloudStorageAccount" $accountCredentials, $true
	#Create table client
	$tableClient = $storageAccount.CreateCloudTableClient()
	#Get a reference to CloudTable object
	$table = $tableClient.GetTableReference($tableName)
	#Try to create table if it does not exist
	$table.CreateIfNotExists()
  
  	$entity = New-Object "Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity" $PartitionKey, $RowKey
    $entity.Properties.Add("ConfigurationValue", $value)
    $result = $table.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Insert($entity))
}

Function Create-Deployment($package_url, $service, $slot, $config){
    $opstat = New-AzureDeployment -Slot $slot -Package $package_url -Configuration $config -ServiceName $service -Label "ALL in ONE" 
}
  
Function Upgrade-Deployment($package_url, $service, $slot, $config){
    $setdeployment = Set-AzureDeployment -Upgrade -Slot $slot -Package $package_url -Configuration $config -ServiceName $service -Force
}
 
Function Check-Deployment($service, $slot){
    $completeDeployment = Get-AzureDeployment -ServiceName $service -Slot $slot
    $completeDeployment.deploymentid
}

Function GetConfig($_configSource, $_MediaButlerStorageConn) {
    
    $invocation = (Get-Variable MyInvocation).Value
    $localPath=$invocation.InvocationName.Substring(0,$invocation.InvocationName.IndexOf($invocation.MyCommand))
    $configFile=$localPath +"ServiceConfiguration.Cloud.cscfg"
    
    If (Test-Path $configFile){
	    Remove-Item $configFile
    }

    Invoke-WebRequest $_configSource -OutFile $configFile 

     [xml]$configXml =Get-Content $configFile

	 # We only have 1 setting
	  $configXml.ServiceConfiguration.Role[0].ConfigurationSettings.Setting.value=$_MediaButlerStorageConn
	  $configXml.ServiceConfiguration.Role[1].ConfigurationSettings.Setting.value=$_MediaButlerStorageConn

	 # changed with SDK 2.5
     #$configXml.ServiceConfiguration.Role[0].ConfigurationSettings.Setting[0].value=$_MediaButlerStorageConn
     #$configXml.ServiceConfiguration.Role[0].ConfigurationSettings.Setting[1].value=$_MediaButlerStorageConn 
     #$configXml.ServiceConfiguration.Role[1].ConfigurationSettings.Setting[0].value=$_MediaButlerStorageConn
     #$configXml.ServiceConfiguration.Role[1].ConfigurationSettings.Setting[1].value=$_MediaButlerStorageConn
  
     $configXml.Save($configFile)

     return $configFile
}

Function DeployBulter($_serviceName,$_slot,$_package_url,$_serviceLocation,$_config_Url,$_sExternalConnString){


    $config = GetConfig -_configSource $_config_Url -_MediaButlerStorageConn $_sExternalConnString
    #Cloud Services
    # check for existence
    $cloudService = Get-AzureService -ServiceName $_serviceName -ErrorVariable errPrimaryService -Verbose:$false -ErrorAction "SilentlyContinue"
    if ($cloudService -eq $null){
        #Create New CLoud Services
        New-AzureService -ServiceName $_serviceName -Location $_serviceLocation -ErrorVariable errPrimaryService -Verbose:$false 
                    # -ErrorAction "SilentlyContinue" | Out-Null
    }
    #Get DEployment Data
    $deployment = Get-AzureDeployment -ServiceName $_serviceName -Slot $_slot -ErrorAction silentlycontinue
    if ($deployment.Name -eq $null) {
            Write-Host "No deployment is detected. Creating a new deployment. "
            Create-Deployment -package_url $_package_url -service $_serviceName -slot $_slot -config $config 
            Write-Host "New Deployment created"
 
        } else {
            Write-Host "Deployment exists in $service.  Upgrading deployment."
            Upgrade-Deployment -package_url $_package_url -service $_serviceName -slot $_slot -config $config
            Write-Host "Upgraded Deployment"
        }
    $deploymentid = Check-Deployment -service $_serviceName -slot $_slot
    Write-Host "Deployed to $_serviceName with deployment id $deploymentid"

    Remove-Item  $config
}


try
{

    #1. setup
    #1.1 Set-AzureSubscription $azureSubscriptionName
         Set-AzureSubscription -SubscriptionName $azureSubscriptionName  -CurrentStorageAccountName $butlerStorageAccountName
	     Select-AzureSubscription -SubscriptionName  $azureSubscriptionName
    #2. Create Media Butler Configuration Table
        $sKey=Get-AzureStorageKey -StorageAccountName $butlerStorageAccountName
        $sExternalConnString='DefaultEndpointsProtocol=https;AccountName=' + $butlerStorageAccountName +';AccountKey='+ $sKey.Primary +''
        $butlerStorageContext= New-AzureStorageContext -StorageAccountKey $skey.Primary -StorageAccountName $butlerStorageAccountName
     
        New-AzureStorageTable -Context $butlerStorageContext -Name "ButlerConfiguration"
   
    #3. Create Queues butlerfailed,butlersend
        New-AzureStorageQueue -Name "butlerfailed" -Context $butlerStorageContext
        New-AzureStorageQueue -Name "butlersend" -Context $butlerStorageContext
        New-AzureStorageQueue -Name "butlersuccess" -Context $butlerStorageContext
		
	#4. Create Bin Container
        New-AzureStorageContainer -Name "mediabutlerbin" -Context $butlerStorageContext -Permission Off

    #5. Media Butler config Data
           InsertButlerConfig -PartitionKey "MediaButler.Common.workflow.ProcessHandler" -RowKey "IsMultiTask" -value "1" -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
           InsertButlerConfig -PartitionKey "MediaButler.Workflow.ButlerWorkFlowManagerWorkerRole" -RowKey "roleconfig" -value "{""MaxCurrentProcess"":1,""SleepDelay"":5,""MaxDequeueCount"":3}" -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
           InsertButlerConfig -PartitionKey "general" -RowKey "BlobWatcherPollingSeconds" -value "5" -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
           InsertButlerConfig -PartitionKey "general" -RowKey "FailedQueuePollingSeconds" -value "5" -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
           InsertButlerConfig -PartitionKey "general" -RowKey "MediaServiceAccountName" -value $MediaServiceAccountName -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
           InsertButlerConfig -PartitionKey "general" -RowKey "MediaStorageConn" -value $MediaStorageConn -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
           InsertButlerConfig -PartitionKey "general" -RowKey "PrimaryMediaServiceAccessKey" -value $PrimaryMediaServiceAccessKey -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
           InsertButlerConfig -PartitionKey "general" -RowKey "SuccessQueuePollingSeconds" -value "5" -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
      
		    # AlternateIdStep config data (use original video name)
            InsertButlerConfig -PartitionKey "MediaButler.Common.workflow.ProcessHandler" -RowKey "alternativeidvideoname.StepConfig" -value "{""OriginType"":""$AlternateIdConfig""}" -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
           
            # ServiceBus config data
            InsertButlerConfig -PartitionKey "MediaButler.Common.workflow.ProcessHandler" -RowKey "servicebus.StepConfig" -value "{""ConnectionString"":""$ServiceBusConn"", ""Topic"":""$ServiceBusTopic"", ""Subscription"":""$ServiceBusSubscription""}" -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
    

    #6. Process Sample: Encode Multibitrate MP4
        $butlerContainerStageName="testservicebus"
        $context=$butlerContainerStageName + ".Context"
        $chain=$butlerContainerStageName + ".ChainConfig"
        if ($SendGridStepConfig -ne "")
                        {
            #USe SendGrid
            $processChain="[{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.MessageHiddeControlStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.IngestMultiMezzamineFilesStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.StandarEncodeStep"",""ConfigKey"":""StandarEncodeStep""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.DeleteOriginalAssetStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.UpdateAlternateIDStep"",""ConfigKey"":""alternativeidvideoname""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.CreateStreamingLocatorStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.CreateSasLocatorStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.ServiceBus.SendMessageTopicStep"",""ConfigKey"":""servicebus""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.SendGridStep"",""ConfigKey"":""SendGridStep""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.SendMessageBackStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.MessageHiddeControlStep"",""ConfigKey"":""""}]"
			InsertButlerConfig -PartitionKey "MediaButler.Common.workflow.ProcessHandler" -RowKey "SendGridStep.StepConfig" -value $SendGridStepConfig -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
        }
        else
                    {
            #Not use SendGridNotiifcation in sample process
            $processChain="[{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.MessageHiddeControlStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.IngestMultiMezzamineFilesStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.StandarEncodeStep"",""ConfigKey"":""StandarEncodeStep""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.DeleteOriginalAssetStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.UpdateAlternateIDStep"",""ConfigKey"":""alternativeidvideoname""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.CreateStreamingLocatorStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.CreateSasLocatorStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.ServiceBus.SendMessageTopicStep"",""ConfigKey"":""servicebus""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.SendMessageBackStep"",""ConfigKey"":""""},{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.MessageHiddeControlStep"",""ConfigKey"":""""}]"
        }
    
  
        New-AzureStorageContainer -Name $butlerContainerStageName -Context $butlerStorageContext -Permission Off
  
        InsertButlerConfig -PartitionKey "MediaButler.Common.workflow.ProcessHandler" -RowKey $context -value "{""AssemblyName"":""MediaButler.BaseProcess.dll"",""TypeName"":""MediaButler.BaseProcess.ButlerProcessRequest"",""ConfigKey"":""""}" -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
        InsertButlerConfig -PartitionKey "MediaButler.Common.workflow.ProcessHandler" -RowKey $chain -value $processChain -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"  
        InsertButlerConfig -PartitionKey "MediaButler.Workflow.WorkerRole" -RowKey "ContainersToScan" -value $butlerContainerStageName -accountName $butlerStorageAccountName -accountKey $sKey -tableName "ButlerConfiguration"



    #7. Deploy Cloud Services
    DeployBulter -_serviceName $serviceName -_package_url $package_url -_slot $slot -_serviceLocation $serviceLocation -_config_Url $config_Url -_sExternalConnString $sExternalConnString
}
catch 
{
    $ErrorMessage = $_.Exception.Message
    Write-Host  $ErrorMessage
    
}