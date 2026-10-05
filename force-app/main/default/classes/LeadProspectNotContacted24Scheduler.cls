/**
 * @description   Schedulable entry point for LeadProspectNotContacted24Batch.
 * @author        Anshita Chanda
 * @date          2026-08-10
 */
public without sharing class LeadProspectNotContacted24Scheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    Database.executeBatch(new LeadProspectNotContacted24Batch(), 10);
  }
}