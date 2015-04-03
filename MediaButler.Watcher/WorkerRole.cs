using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.WindowsAzure;
using Microsoft.WindowsAzure.Diagnostics;
using Microsoft.WindowsAzure.ServiceRuntime;
using Microsoft.WindowsAzure.Storage;
using Microsoft.WindowsAzure.Storage.Auth;
using Microsoft.WindowsAzure.Storage.Queue;
using Microsoft.WindowsAzure.Storage.Blob;
using Newtonsoft.Json;
using MediaButler.Common;
using Microsoft.Azure;

namespace MediaButler.Watcher
{
    public partial class WorkerRole : RoleEntryPoint
    {
        private readonly CancellationTokenSource cancellationTokenSource = new CancellationTokenSource();
        private readonly ManualResetEvent runCompleteEvent = new ManualResetEvent(false);
        private string[] ContainersToScan = null;  // filled in in OnStart

        private const int ScanSleepInMS = 30000;    // sleep this long between container scans

        public override void Run()
        {
            Trace.TraceInformation("MediaButler.Watcher is running");

            try
            {
                this.RunAsync(this.cancellationTokenSource.Token).Wait();
            }
            finally
            {
                this.runCompleteEvent.Set();
            }
        }

        public override bool OnStart()
        {
            // Set the maximum number of concurrent connections
            ServicePointManager.DefaultConnectionLimit = 12;

            // For information on handling configuration changes
            // see the MSDN topic at http://go.microsoft.com/fwlink/?LinkId=166357.

            bool result = base.OnStart();
   
            // Get list of input containers to scan...
            string s = MediaButler.Common.Configuration.GetConfigurationValue("ContainersToScan", "MediaButler.Workflow.WorkerRole");
            var containers = s.Split(',');
            ContainersToScan = containers;

            Trace.TraceInformation("MediaButler.Watcher has been started, Containers=({0})", String.Join(", ", ContainersToScan));

            return result;
        }

        public override void OnStop()
        {
            Trace.TraceInformation("MediaButler.Watcher is stopping");

            this.cancellationTokenSource.Cancel();
            this.runCompleteEvent.WaitOne();

            base.OnStop();

            Trace.TraceInformation("MediaButler.Watcher has stopped");
        }

        private async Task RunAsync(CancellationToken cancellationToken)
        {

            string storageAccountString = CloudConfigurationManager.GetSetting(Configuration.ButlerStorageConnectionConfigurationKey);

            // Kick off the tasks that will handle watching for the two completed request queues.
            var taskFailedRequests = Task.Run(() => JobManager.getWorkflowFailedOperations(cancellationToken, storageAccountString));
            var taskSuccessfulRequests = Task.Run(() => JobManager.getWorkflowSuccessOperations(cancellationToken, storageAccountString));
            // Note: list of containers was set in OnStart.
            var taskProcessIncomingJobs = Task.Run(() => BlobWatcher.runInboundJobWatcher(cancellationToken, storageAccountString, ContainersToScan));

            Task.WaitAll(taskFailedRequests, taskSuccessfulRequests, taskProcessIncomingJobs);
        }
    }
}
