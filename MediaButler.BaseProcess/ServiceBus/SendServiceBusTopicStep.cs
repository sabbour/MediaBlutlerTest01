using Microsoft.ServiceBus;
using Microsoft.ServiceBus.Messaging;
using Microsoft.WindowsAzure.MediaServices.Client;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace MediaButler.BaseProcess.ServiceBus
{
    public class ExportDataAsset
    {
        public string AssetId { get; set; }
        public string AlternateId { get; set; }
        public string Smooth { get; set; }
        public string HLS { get; set; }
        public string DASH { get; set; }
    }

    public class ServiceBusData
    {
        public string ConnectionString { get; set; }
        public string Topic { get; set; }
        public string Subscription { get; set; }

    }

    class SendMessageTopicStep : MediaButler.Common.workflow.StepHandler
    {
        private ButlerProcessRequest myRequest;
        private CloudMediaContext _MediaServicesContext;
        private ServiceBusData myServiceBusData;
        private ExportDataAsset myData;
        public override void HandleCompensation(MediaButler.Common.workflow.ChainRequest request)
        {
            //Standar Step Compesnation, only LOG
            myRequest = (ButlerProcessRequest)request;
            string errorTxt = string.Format("[{0}] process Type {1} instance {2} has not compensation method", this.GetType().FullName, myRequest.ProcessTypeId, myRequest.ProcessInstanceId);
            Trace.TraceWarning(errorTxt);
        }

        private void SendMessage(string jsonMessage)
        {
            var namespaceManager = NamespaceManager.CreateFromConnectionString(myServiceBusData.ConnectionString);
            // Create the topic if it does not exist already
            if (!namespaceManager.TopicExists(myServiceBusData.Topic))
            {
                namespaceManager.CreateTopic(myServiceBusData.Topic);
            }
            if (!namespaceManager.SubscriptionExists(myServiceBusData.Topic, myServiceBusData.Subscription))
            {
                namespaceManager.CreateSubscription(myServiceBusData.Topic, myServiceBusData.Subscription);
            }
            TopicClient Client = TopicClient.CreateFromConnectionString(myServiceBusData.ConnectionString, myServiceBusData.Topic);
            Client.Send(new BrokeredMessage(jsonMessage));
        }
        private void MapInfo()
        {
            myData = new ExportDataAsset();
            var theAsset = (from m in _MediaServicesContext.Assets select m).Where(m => m.Id == myRequest.AssetId).FirstOrDefault();

            myData.AssetId = theAsset.Id;
            myData.AlternateId = theAsset.AlternateId;

            var assetFilesALL = theAsset.AssetFiles.ToList();

            foreach (ILocator locator in theAsset.Locators)
            {
                if (locator.Type == LocatorType.OnDemandOrigin)
                {
                    var ismfile = assetFilesALL.Where(f => f.Name.ToLower().EndsWith(".ism", StringComparison.OrdinalIgnoreCase)).FirstOrDefault();

                    myData.Smooth = locator.Path + ismfile.Name + "/manifest";
                    myData.HLS = locator.Path + ismfile.Name + "/manifest(format=m3u8-aapl)";
                    myData.DASH = locator.Path + ismfile.Name + "/manifes(format=mpd-time-csf)";
                }
            }
        }
        public override void HandleExecute(MediaButler.Common.workflow.ChainRequest request)
        {
            //Standar Init Step activities
            myRequest = (ButlerProcessRequest)request;
            _MediaServicesContext = new CloudMediaContext(myRequest.MediaAccountName, myRequest.MediaAccountKey);
            //Read ServiceBus configuration from Step configuration
            myServiceBusData = Newtonsoft.Json.JsonConvert.DeserializeObject<ServiceBusData>(this.StepConfiguration);
            //Map info to output
            MapInfo();
            string jsonMessage = Newtonsoft.Json.JsonConvert.SerializeObject(this.myData);
            //Send Message
            this.SendMessage(jsonMessage);
            //step finish

        }
    }

}
