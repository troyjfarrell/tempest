# Sandstorm - Personal Cloud Sandbox
# Copyright (c) 2014 Sandstorm Development Group, Inc. and contributors
# All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

@0xc8d91463cfc4fb4a;

$import "/capnp/c++.capnp".namespace("sandstorm");
using Go = import "/go.capnp";
$Go.package("grain");
$Go.import("sandstorm.org/go/tempest/capnp/grain");

using Util = import "util.capnp";
using Powerbox = import "powerbox.capnp";
using Activity = import "activity.capnp";
using Identity = import "identity.capnp";

# ========================================================================================
# Runtime interface

interface SandstormApi(AppObjectId) {
  # The Sandstorm platform API, exposed as the default capability over the two-way RPC connection
  # formed with the application instance.  This object specifically represents the supervisor
  # for this application instance -- two different application instances (grains) never share a
  # supervisor.
  #
  # `AppObjectId` is the format in which the application identifies its persistent objects which
  # can be saved from the outside; see `AppPersistent`, below.

  # TODO(soon):  Read the grain title as set by the user.  Also have interface to offer a new
  #   title and icon?

  deprecatedPublish @0 ();
  deprecatedRegisterAction @1 ();
  # These powerbox-related methods were never implemented. Eventually it was decided that they
  # specified the wrong model.

  shareCap @2 (cap :Capability, displayInfo :Powerbox.PowerboxDisplayInfo)
           -> (sharedCap :Capability, link :SharingLink);
  # Share a capability, so that it may safely be sent to another user.  `sharedCap` is a wrapper
  # (membrane) around `cap` which can have a petname assigned and can be revoked via `link`.  The
  # share is automatically revoked if `link` is discarded.  If `cap` is persistable, then both
  # `sharedCap` and `link` also are.
  #
  # This method is intended to be used by programs that actually implement a communications link
  # over which a capability could be sent from one user to another.  For example, a chat app would
  # use this to prepare a capability to be embedded into a message.  In these cases, capabilities
  # may be shared without going through the system sharing UI, and therefore the application must
  # set up the sharing link itself.
  #
  # In general, you should NOT call this on a capability that you will then pass to
  # `SessionContext.offer()`.

  shareView @3 (view :UiView) -> (sharedView :UiView, link :ViewSharingLink);
  # Like `shareCap` but with extra options for sharing a UiView, such as setting a role and
  # permissions.

  save @8 (cap :Capability, label :Util.LocalizedText) -> (token :Data);
  # Saves a persistent capability and returns a token which can be used to restore it later
  # (including in a future run of the app) via `restore()` (below). Not all capabilities can be
  # saved -- check the documentation for the capability you are using to see if it is described as
  # "persistent".
  #
  # The grain owner will be able to inspect saved capabilities via the UI. `label` will be shown
  # there and should briefly describe what this capability is used for.
  #
  # To see how to make your own app's objects persistent, see the `AppPersistent` interface defined
  # later in this file. Note that it's perfectly valid to pass your app's own capabilities to
  # `save()`, if they are persistent in this way.
  #
  # (Under the hood, `SandstormApi.save()` calls the capability's `AppPersistent.save()` method,
  # then stores the result in a table indexed by the new randomly-generated token. The app CANNOT
  # call `AppPersistent.save()` on external capabilities itself; such calls will be blocked by the
  # supervisor (and the result would be useless to you anyway, because you have no way to restore
  # it). You must use `SandstormApi.save()` so that saved capabilities can be inspected by the
  # user.)

  restore @4 (token :Data) -> (cap :Capability);
  # Given a token previously returned by `save()`, get the capability it pointed to. The returned
  # capability should implement the same interfaces as the one you saved originally, so you can
  # downcast it as appropriate.

  drop @5 (token :Data);
  # Deletes the token and frees any resources being held with it. Once drop()ed, you can no longer
  # restore() the token. This call is idempotent: it is not an error to `drop()` a token that has
  # already been dropped.

  deleted @6 (ref :AppObjectId);
  # Notifies the supervisor that an object hosted by this application has been deleted, and
  # therefore all references to it may as well be dropped. This affects *incoming* references,
  # whereas `drop()` affects *outgoing*.

  stayAwake @7 (displayInfo :Activity.NotificationDisplayInfo,
                notification :Activity.OngoingNotification)
            -> (handle :Util.Handle);
  # Requests that the app be allowed to continue running in the background, even if no user has it
  # open in their browser. An ongoing notification is delivered to the user who owns the grain to
  # let them know of this. The user may cancel the notification, in which case the app will no
  # longer be kept awake. If not canceled, the app remains awake at least until it drops `handle`.
  #
  # Unlike other ongoing notifications, `notification` in this case need not be persistent (since
  # the whole point is to prevent the app from restarting), and `handle` is not persistent.
  #
  # WARNING: A machine failure or similar situation can still cause the app to shut down at any
  #   time. Currently, the app will NOT be restarted after such a failure.
  #
  # TODO(someday): We could make `handle` be persistent. If the app persists it -- and if
  #   `notification` is persistent -- we would automatically restart the app after an unexpected
  #   failure.

  backgroundActivity @9 (event :Activity.ActivityEvent);
  # Post an activity event to the grain's activity log that was *not* initiated by any particular
  # user. For activity that should be attributed to a user, use SessionContext.activity().

  getIdentityId @10 (identity: Identity.Identity) -> (id :Data);
  # Gets the ID of the identity, as it would appear in UserInfo.identityId.
  #
  # This method is here on `SandstormApi` rather than on `Identity` in order to ease a possible
  # future transition to a model where identity IDs are not globally stable and each grain has a
  # separate (possibly incompatible) map from identity ID to account ID.

  schedule @11 ScheduledJob;
  # Schedule a callback to be executed in the future.
  #
  # The job may be scheduled to execute once at a specific time, or periodically. See
  # `ScheduledJob` for more information.
  #
  # When this method returns, the job will have been scheduled.
}

struct ScheduledJob {
  # A job to be scheduled by `SandstormApi.schedule()`.

  name @0 :Util.LocalizedText;
  # A name for the job. This will be used to describe the job to the user.

  callback @1 :Callback;
  # A callback to actually execute when it is time to run the job.
  #
  # In addition to implementing the `Callback` interface below, this must also
  # implement `AppPersistent`. When a request to schedule the job is made, Sandstorm
  # will `save()` the callback, and then later `restore()` it when it is time to
  # run the job. See `AppPersistent` for more details on how this works.
  #
  # Note that, in some circumstances, the app may need to save some information
  # locally to recognize the task. There is a possibility that between scheduling
  # the job and actually saving the information, The app may be killed, the server
  # may crash, or some other failure may occur that prevents the app from saving
  # the information. We recommend dealing with this in one of the following ways:
  #
  # - Where possible, save all needed information in the `objectId` returned
  #   by `AppPersistent.save()`; this avoids the race condition entirely.
  # - Otherwise, in your implementation of `MainView.restore()`, if you are asked
  #   to restore a callback you don't recognize, return a dummy callback that does
  #   nothing, and returns `cancelFutureRuns = true`. This will cause Sandstorm to
  #   cancel and delete the unknown job.
  #
  # When the callback is called, Sandstorm will avoid killing the grain until the callback returns.
  # If the callback throws a "disconnected" exception, or if Sandstorm is forced to kill the
  # grain for some reason, the callback will be retried. After a limited number of failed retries,
  # Sandstorm may alert the owner to a problem and stop retrying.

  interface Callback {
    run @0 () -> (cancelFutureRuns :Bool = false);
    # Run the job. If the return value has `cancelFutureRuns = true` and this is a periodic job,
    # the job will be cancelled and will not be run again.
  }

  schedule :union {
  # The actual schedule of the job.

    oneShot :group {
    # Run the job exactly once.

      when @2 :Util.DateInNs;
      # The time at which the job should be run.

      slack @3 :Util.DurationInNs;
      # In order to improve resource utilization, Sandstorm prefers imprecise
      # scheduling -- this allows it to choose a time of low activity to invoke
      # the callback. The `slack` field tells Sandstorm how much freedom it
      # has -- it may schedule the task any time between `when` and `when +
      # slack`. A value of zero for `slack` is special: it is equivalent to
      # 1/8th of the difference between now and `when` -- this sets the window
      # adaptively, such that the further in the future the event is scheduled,
      # the more slack it has. You must explicitly set a non-zero value if you
      # need better precision. Additionally, the value must be greater than
      # `minimumSchedulingSlack`, or an exception will be thrown. If you need
      # better precision than this, you should schedule a callback for slightly
      # before the target time, then countdown the remaining time in-process.
    }

    periodic @4 :SchedulingPeriod;
    # Run the job on a regular interval.
    #
    # In order to improve resource utilization, Sandstorm prefers imprecise
    # scheduling -- this allows it to choose a time of low activity to
    # invoke the callback. Therefore, Sandstorm guarantees that the callback
    # will be called once per scheduling period, but does not make any guarantees
    # about exactly when in that period the call will occur. If you need more
    # precise scheduling, you will need to use `oneShot`, and schedule the next
    # occurance from the callback itself, before returning.
  }
}

const minimumSchedulingSlack :Util.DurationInNs = 300000000000;
# 5 minutes: The minimum value allowable for the `slack` parameter passed to `scheduleAt()`.

enum SchedulingPeriod {
  annually @3;
  monthly @2;
  weekly @4;
  daily @1;
  hourly @0;
}

interface UiView @0xdbb4d798ea67e2e7 {
  # Implements a user interface with which a user can interact with the grain.  We call this a
  # "view" because a single grain may actually have multiple "views" that provide different
  # functionality or represent multiple logical objects in the same physical grain.
  #
  # When an application starts up, it must export an instance of UiView as its starting
  # capability on the Cap'n Proto two-party connection.  This represents the grain's main view and
  # is what the user will see when they open the grain.
  #
  # It is possible for a grain to export additional views via the usual powerbox mechanisms.  For
  # instance, a spreadsheet app might let the user create a "view" of a few cells of the
  # spreadsheet, allowing them to share those cells to another user without sharing the entire
  # sheet.  To accomplish this, the app would create an alternate UiView object that implements
  # an interface just to those cells, and then would use `UiSession.offer()` to offer this object
  # to the user.  The user could then choose to open it, share it, save it for later, etc.
  #
  # TODO(apibump): Parameterize UiView on:
  # - A struct type representing permissions, which must have only boolean fields, each annotated
  #   with a PermissionDef. Replace all istances of PermissionSet with this.
  # - An enum type representing roles, each annotated with its permission set and a RoleDef.
  #   (Requires Cap'n Proto changes to allow parametirizing on enum types, I guess...)
  # - An enum type representing activity event types, each annotated with an ActivityTypeDef.

  getViewInfo @0 () -> ViewInfo;
  # Get metadata about the view, especially relating to sharing.

  struct ViewInfo {
    permissions @0 :List(PermissionDef);
    # List of permission bits which apply to this view.  Permissions typically include things like
    # "read" and "write".  When sharing a view, the sending user may select a set of permissions to
    # grant to the receiving user, and may modify this set later on.  When a new user interface
    # session is initiated, the platform indicates which permissions the user currently has.
    #
    # The grain's owner always has all permissions.
    #
    # It is important that new versions of the app only add new permissions, never remove existing
    # ones, since permission IDs are indexes into the list and persist through upgrades.
    #
    # In a true capability system, permissions would normally be implemented by wrapping the main
    # view in filters that prohibit disallowed actions.  For example, to give a user read-only
    # access to a grain, you might wrap its UiView in a wrapper that checks all incoming requests
    # and disallows the ones that would modify the content.  However, this approach does not work
    # terribly well for UiView for a few reasons:
    #
    # - For complex UIs, HTTP is often the wrong level of abstraction for this kind of filtering.
    #   It _may_ work for modern apps that push all UI logic into static client-side Javascript and
    #   only serve RPCs over dynamic HTTP, but it won't work well for many legacy apps, and we want
    #   to be able to port some of those apps to Sandstorm.
    #
    # - If a UiView is reshared several times, each time adding a new filtering wrapper, then
    #   requests could get slow as they have to pass through all the separate filters.  This would
    #   be especially bad if some of the filters live in other grains, as those grains would have
    #   to spin up whenever the resulting view is used.
    #
    # - Compared to computers, humans are relatively less likely to be vulnerable to confused
    #   deputy attacks and relatively more likely to be confused by the concept of having multiple
    #   capabilities to the same object that provide different access levels.  For example, say
    #   Alice and Bob both share the same document to Carol, but Alice only grants read access
    #   while Bob gives read/write.  Carol should only see one instance of the document in her
    #   grain list and she should see the read/write interface when she opens it.  But this instance
    #   isn't simply the one she got from Bob -- if Bob revokes his share but Alice continues to
    #   share read rights, Carol should now see the read-only interface when she opens the same
    #   grain.
    #
    # To solve all three problems, we have permission bits that are processed when creating a new
    # session.  Instead of filtering individual requests, wrappers of UiView only need to filter
    # calls to `newSession()` in order to restrict the permission set as appropriate.  Once a
    # session is thus created, it represents a direct link to the target grain.  Also, the platform
    # can implement special handling of sharing and permission bits that allow it to recognize when
    # two UiViews are really the same view with different permissions applied, and can then combine
    # them in the UI as appropriate.
    #
    # Implementation-wise, in addition to the permissions enumerated here, there is an additional
    # "is human" pseudopermission provided by the Sandstorm platform, which is invisible to apps,
    # but affects how UiView capabilities may be used.  In particular, all users are said to possess
    # the "is human" pseudopermission, whereas all other ApiTokenOwners do not, and by default, the
    # privilege is not passed on.  All method calls on UiView require that the caller have the "is
    # human" permission.  In practical terms, this means that grains can pass around UiView
    # capabilities, but only users can actually use them to open sessions.
    #
    # It is actually entirely possible to implement a traditional filtering membrane around a
    # UiView, perhaps to implement a kind of access that can't be expressed using the permission
    # bits defined by the app.  But doing so will be awkward, slow, and confusing for all the
    # reasons listed above.

    roles @1 :List(RoleDef);
    # Choosing individual permissions is not very intuitive for most users.  Therefore, the sharing
    # interface prefers to offer the user a list of "roles" to assign to each recipient.  For
    # example, a document might have roles like "editor" and "viewer".  Each role corresponds to
    # some list of permissions.  The application may define a set of roles to offer via this list.
    #
    # In addition to the roles in this list, the sharing interface will always offer a "full access"
    # or "same as me" option.  So, it only makes sense to define roles that represent less than
    # "full access", and leaving the role list entirely empty is reasonable if there are no such
    # restrictions to offer.
    #
    # It is important that new versions of the app only add new roles, never remove existing ones,
    # since role IDs are indexes into the list and persist through upgrades.

    deniedPermissions @2 :Identity.PermissionSet;
    # Set of permissions which will be removed from the permission set when creating a new session
    # though this object.  This set should be empty for the grain's main UiView, but when that view
    # is shared with less than full access, recipients will get a proxy UiView which has a non-empty
    # `deniedPermissions` set.
    #
    # It is not the caller's responsibility to enforce this set.  It is provided mainly so that the
    # sharing UI can avoid offering options to the user that don't make sense.  For instance, if
    # Alice has read-only access to a document and wishes to share the document to Bob, the sharing
    # UI should not offer Alice the ability to share write access, because she doesn't have it in
    # the first place.  The sharing UI figures out what Alice has by examining `deniedPermissions`.

    matchRequests @3 :List(Powerbox.PowerboxDescriptor);
    # Indicates what kinds of powerbox requests this grain may be able to fulfill. If the grain
    # is chosen by the user during a powerbox request, then `newRequestSession()` will be called
    # to set up the embedded UI session.

    matchOffers @4 :List(Powerbox.PowerboxDescriptor);
    # Indicates what kinds of powerbox offers this grain is interested in accepting. If the grain
    # is chosen by the user during a powerbox offer, then `newOfferSession()` will be called
    # to start a session around this.

    appTitle @5 :Util.LocalizedText;
    # Title for the app of which this grain is an instance.

    grainIcon @6 :Util.StaticAsset;
    # Icon for the app of which this grain is an instance, suitable for display in a grain list.

    eventTypes @7 :List(Activity.ActivityTypeDef);
    # Definitions of activity event types generated by this grain. Each activity event is tagged
    # with one of these types. Typed events potentially allow for advanced filtering options and
    # compact activity summaries.
  }

  struct PowerboxTag {
    # Tag to be used in a `PowerboxDescriptor` to describe a `UiView`.

    title @0 :Text;
    # The title of the `UiView` as chosen by the introducer identity.
  }

  newSession @1 (userInfo :Identity.UserInfo, context :SessionContext,
                 sessionType :UInt64, sessionParams :AnyPointer,
                 tabId :Data)
             -> (session :UiSession);
  # Start a new user interface session.  This happens when a user first opens the view, or when
  # the user returns to a tab that has been inactive long enough that the server was killed off in
  # the meantime.
  #
  # `userInfo` specifies the user's display name and permissions, as authenticated by the system.
  #
  # `context` contains callbacks that can be used to invoke system functionality in the context of
  # the session, such as displaying the powerbox.
  #
  # `sessionType` is the type ID specifying the interface which the returned `session` should
  # implement.  All views should support the `WebSession` interface to support opening the view
  # in a browser.  Other session types might be useful for e.g. desktop and mobile apps.
  #
  # `sessionParams` is a struct whose type is specified by the session type.  By convention, this
  # struct should be defined nested in the session interface type with name "Params", e.g.
  # `WebSession.Params`.  This struct contains some arbitrary startup information.
  #
  # `tabId` is a stable identifier for the "tab" (as in, Sandstorm sidebar tab) in which the grain
  # is being displayed. A single tab may span multiple UiSessions, for instance if the user
  # suspends their laptop and then restores later, or if the grain crashes. More importantly,
  # `tabId` allows multiple grains being composed in the same tab to coordinate. For example, when
  # a grain is embedded in the powerbox UI to respond to a request, it sees the same `tabId` as
  # the requesting grain. Similarly, when a grain embeds other grains within iframes within its
  # own UI, they will all see the same `tabId`. One particular case where `tabId` is useful is
  # in implementing an `EmailVerifier` that cannot be MITM'd. NOTE: `tabId` should NOT be presumed
  # to be a secret, although no two tabs in all of time will have the same `tabId`.
  #
  # For API requests, `tabId` uniquely identifies the token, and so can be used to correlate
  # multiple requests from the same client.

  newRequestSession @2 (userInfo :Identity.UserInfo, context :SessionContext,
                        sessionType :UInt64, sessionParams :AnyPointer,
                        requestInfo :List(Powerbox.PowerboxDescriptor), tabId :Data)
                    -> (session :UiSession);
  # Creates a new session based on a powerbox request. `requestInfo` is the subset of the original
  # request description which matched descriptors that this grain indicated it provides via
  # `ViewInfo.matchRequests`. The list is also sorted with the "best match" first, such that
  # it is reasonable for a grain to ignore all descriptors other than the first.
  #
  # Keep in mind that, as with any other session, the UiSession capability could become
  # disconnected randomly and the front-end will then reconnect by calling `newRequestSession()`
  # again with the same parameters. Generally, apps should avoid storing any session-related state
  # on the server side; it's easy to use client-side sessionStorage instead.
  #
  # The `tabId` passed here identifies the requesting tab; see docs under `newSession()`.

  newOfferSession @3 (userInfo :Identity.UserInfo, context :SessionContext,
                      sessionType :UInt64, sessionParams :AnyPointer,
                      offer :Capability, descriptor :Powerbox.PowerboxDescriptor,
                      tabId :Data)
                  -> (session :UiSession);
  # Creates a new session based on a powerbox offer. `offer` is the capability being offered and
  # `descriptor` describes it.
  #
  # By default, an "offer" session is displayed embedded in the powerbox much like a "request"
  # session is. If the the session implements a quick action -- say "share to friend by email" --
  # then it may make sense for it to remain embedded, returning the user to the offering app when
  # done. The app may call `SessionContext.close()` to indicate that it's time to close. However,
  # in some cases it makes a lot of sense for the app to become "full-frame", for example a
  # document editor app accepting a document offer may want to then open the editor for long-term
  # use. Such apps should call `SessionContext.openView()` to move on to a full-fledged session.
  # Finally, some apps will take an offer, wrap it in some filter, and then make a new offer of the
  # wrapped capability. To that end, calling `SessionContext.offer()` will end the offer session
  # but immediately start a new offer interaction in its place using the new capability.
  #
  # Keep in mind that, as with any other session, the UiSession capability could become
  # disconnected randomly and the front-end will then reconnect by calling `newOfferSession()`
  # again with the same parameters. Generally, apps should avoid storing any session-related state
  # on the server side; it's easy to use client-side sessionStorage instead. (Of course, if the
  # session calls `SessionContext.openView()`, the new view will be opened as a regular session,
  # not an offer session.)
  #
  # The `tabId` passed here identifies the offering tab; see docs under `newSession()`.
}

# ========================================================================================
# User interface sessions

interface UiSession {
  # Base interface for UI sessions.  The most common subclass is `WebSession`.
}

interface SessionContext {
  # Interface that the application can use to call back to the platform in the context of a
  # particular session.  This can be used e.g. to ask the platform to present certain system
  # dialogs to the user.

  getSharedPermissions @0 () -> (var :Util.Getter(Identity.PermissionSet));
  # Returns an observer on the permissions held by the user of this session.
  # This observer can be persisted beyond the end of the session.  This is useful for detecting if
  # the user later loses their access and auto-revoking things in that case.  See also `tieToUser()`
  # for an easier way to make a particular capability auto-revoke if the user's permissions change.

  tieToUser @1 (cap :Capability, requiredPermissions :Identity.PermissionSet,
                displayInfo :Powerbox.PowerboxDisplayInfo)
            -> (tiedCap :Capability);
  # Create a version of `cap` which will automatically stop working if the user no longer holds the
  # permissions indicated by `requiredPermissions` (and starts working again if the user regains
  # those permissions).  The capability also appears connected to the user in the sharing
  # visualization.
  #
  # Keep in mind that, security-wise, calling this also implies exposing `tiedCap` to the user, as
  # anyone with a UiView capability can always initiate a session and pass in their own
  # `SessionContext`.  If you need to auto-revoke a capability based on the user's permissions
  # _without_ actually passing that capability to the user, use `getSharedPermissions()` to detect
  # when the user's permissions change and implement it yourself.

  offer @2 (cap :Capability, requiredPermissions :Identity.PermissionSet,
            descriptor :Powerbox.PowerboxDescriptor, displayInfo :Powerbox.PowerboxDisplayInfo);
  # Offer a capability to the user.  A dialog box will ask the user what they want to do with it.
  # Depending on the type of capability (as indicated by `descriptor`), different options may be
  # provided.  All capabilities will offer the user the option to save the capability to their
  # capability/grain store.  Other type-specific actions may be offered by the platform or by other
  # applications.
  #
  # For example, offering a UiView will give the user options like "open in new tab", "save to
  # grain list", and "share with another user".
  #
  # The capability is implicitly tied to the user as if via `tieToUser()`.

  request @3 (query :List(Powerbox.PowerboxDescriptor), requiredPermissions :Identity.PermissionSet)
          -> (cap :Capability, descriptor :Powerbox.PowerboxDescriptor);
  # Although this method exists, it is unimplemented and currently you are meant to use the
  # postMessage api to get a temporary token and then restore it with claimRequest().
  #
  # The postMessage api is an rpc interface so you will have to listen for a `message` callback
  # after sending a postMessage. The postMessage object should have the following form:
  #
  # powerboxRequest:
  #   rpcId: A unique string that should identify this rpc message to the app. You will receive this
  #          id in the callback to verify which message it is referring to.
  #   query: A list of PowerboxDescriptor objects, serialized as a Javascript array of
  #          base64-encoded packed powerbox query descriptors created using the `spk query` tool.
  #   saveLabel: A petname to give this label. This will be displayed to the user as the name
  #          for this capability.
  #
  # e.g.:
  #   window.parent.postMessage({
  #     powerboxRequest: {
  #       rpcId: myRpcId,
  #       query: [
  #         // encoded/packed/base64url of (tags = [(id = 15831515641881813735)])
  #         "EAZQAQEAABEBF1EEAQH_5-Jn6pjXtNsAAAA",
  #       ],
  #       saveLabel: { defaultText: "Linked grain" },
  #     },
  #   }, "*");
  #
  # The postMessage searches for capabilities in the user's powerbox matching the given query and
  # displays a selection UI to the user.
  # This will then initiate a powerbox interaction with the user, and when it is done, a postMessage
  # callback to the grain will occur. You can listen for such a message like so:
  # window.addEventListener("message", function (event) {
  #   if (event.data.rpcId === myRpcId && !event.data.error) {
  #     // Pass `event.data.token` to your app's server and call SessionContext.claimRequest() with
  #     // it. The token is guaranteed to be a URL-safe string. That is, passing it through
  #     // encodeURIComponent() should be a no-op.
  #   }
  # }, false)

  claimRequest @7 (requestToken :Text, requiredPermissions :Identity.PermissionSet)
               -> (cap :Capability);
  # When a powerbox request is initiated client-side via the postMessage API and the user completes
  # the request flow, the Sandstorm shell responds to the requesting app with a token. This token
  # itself is not a SturdyRef, but can be exchanged server-side for a capability which in turn
  # can be save()d to produce a SturdyRef. `claimRequest()` is the method to call to exchange the
  # token for a capability. It must be called within a short period after the powerbox request
  # completes; we recommend that the app immediately send the token up to its server to claim
  # the capability.
  #
  # If you are familiar with OAuth, the `requestToken` can be compared to an OAuth "authorization
  # code", whereas a SturdyRef is like an "access token". The authorization code must be exchanged
  # for an access token in a server-to-server interaction.
  #
  # You might consider an alternative approach in which the client-side response includes a
  # newly-minted SturdyRef directly, avoiding the need for a server-side exchange. The problem with
  # that approach is that it makes SturdyRef leaks more dangerous. If an application leaks one of
  # its SturdyRefs to an attacker, the attacker may then initiate a powerbox request on the client
  # side in which the attacker spoofs the response from the Sandstorm shell to inject the leaked
  # SturdyRef. The app likely will not realize that this SturdyRef was not newly-minted and may
  # then use it in a context where it was not intended. Adding the claimRequest() requirement makes
  # a leaked SturdyRef less likely to be useful to an attacker since the attacker cannot usefully
  # inject the SturdyRef into a subsequent spoofed powerbox response, since a SturdyRef is not
  # usable as a `requestToken`.
  #
  # `requiredPermissions` specifies permissions which must be held on *this* grain by the user
  # who completed the powerbox interaction. (The implicit "can access the grain at all" permission
  # is always treated as a required permission, even if `requiredPermissions` is null or empty.)
  # This way, if a user of a grain connects the grain to other resources, but later has their access
  # to the grain revoked, these connections are revoked as well.
  #
  # Consider this example: Alice owns a grain which implements a discussion forum. At some point,
  # Alice invites Dave to participate in the forum, and she gives him moderator permissions. As
  # part of being a moderator, Dave arranges to have a notification emailed to him whenever a post
  # is flagged for moderation. To set this up, the forum app makes a powerbox request for an email
  # send capability directed to his email address. Later on, Alice decides to demote Dave from
  # "moderator" status to "participant". At this point, Dave should stop receiving email
  # notifications; the capability he introduced in the powerbox request should be revoked. Alice
  # actually has no idea that Dave set up to receive these notifications, so she does not know
  # to revoke it manually; we want it to happen automatically, or at least we want to be able to
  # call Alice's attention to it.
  #
  # To this end, after the Powerbox request is made through Dave and he chooses a capability, the
  # app will call `claimRequest()` and indicate in `requiredPermissions` that Dave must have
  # "moderator" permission. The app then `save()`s the capability. In the future, if Dave has lost
  # this permission, then attempts to `restore()` the SturdyRef will fail.

  fulfillRequest @4 (cap :Capability, requiredPermissions :Identity.PermissionSet,
              descriptor :Powerbox.PowerboxDescriptor, displayInfo :Powerbox.PowerboxDisplayInfo);
  # For sessions started with `newRequestSession()`, fulfills the original request. If only one
  # capability was requested, the powerbox will close upon `fulfillRequest()` being called. If
  # multiple capabilities were requested, then the powerbox remains open and `fulfillRequest()` may
  # be called repeatedly.
  #
  # If the session was not started with `newRequestSession()`, this method is equivalent to
  # `offer()`. This can be helpful when building a UI that can be used both embedded in the
  # powerbox and stand-alone.

  close @5 ();
  # Closes the session.
  # - For regular sessions, the user will be returned to the home screen.
  # - For powerbox "request" sessions, the user will be returned to the main grain selection list.
  # - For powerbox "offer" sessions, the powerbox will be closed and the user will return to the
  #   offering app.
  #
  # Note that in some cases it is possible for the user to return by clicking "back", so the app
  # should not assume that no further requests will happen.

  openView @6 (view :UiView, path :Text = "", newTab :Bool = false);
  # Navigates the user to some other UiView (from the same grain or another), closing the current
  # session. If `view` is null, navigates back to the the current view, in a new session.
  #
  # `path` is an optional path to jump directly to within the new session. For WebSessions, this
  # is appended to the URL, and may include query (search) and fragment (hash) components, but
  # should never start with '/'. Example: "foo/bar?baz=qux#corge"
  #
  # If `newTab` is true, the new session is opened in a new tab.
  #
  # If the current session is a powerbox session, `openView()` affects the top-level tab, thereby
  # closing the powerbox and the app that initiated the powerbox (unless `newTab` is true).

  activity @8 (event :Activity.ActivityEvent);
  # Call each time the user performs some activity that should be logged.
}

# ========================================================================================
# Sharing and Access Control

struct PermissionDef {
  # Metadata describing a permission bit.

  name @3 :Text;
  # Name of the permission, used as an identifier for the permission in cases where string names
  # are preferred. These names will never be used in Cap'n Proto interfaces, but could show up in
  # HTTP or JSON translations, such as in sandstorm-http-bridge's X-Sandstorm-Permissions header.
  #
  # The name must be a valid identifier (alphanumerics only, starting with a letter) and must be
  # unique among all permissions defined for a particular UiView.

  title @0 :Util.LocalizedText;
  # Display name of the permission, e.g. to display in a checklist of permissions that may be
  # assigned when sharing.

  description @1 :Util.LocalizedText;
  # Prose describing what this permission means, suitable for a tool tip or similar help text.

  obsolete @2 :Bool = false;
  # If true, this permission was relevant in a previous version of the application but should no
  # longer be offered to the user in future sharing actions.
}

struct RoleDef {
  # Metadata describing a shareable role.

  title @0 :Util.LocalizedText;
  # Name of the role, e.g. "editor" or "viewer".

  verbPhrase @1 :Util.LocalizedText;
  # Verb phrase describing what users in this role can do with the grain.  Should be something
  # like "can edit" or "can view".  When the user shares the view with others, these verb phrases
  # will be used to populate a drop-list of roles for the user to select.

  description @2 :Util.LocalizedText;
  # Prose describing what this role means, suitable for a tool tip or similar help text.

  permissions @3 :Identity.PermissionSet;
  # Permissions which make up this role.  For example, the "editor" role on a document would
  # typically include "read" and "write" permissions.

  obsolete @4 :Bool = false;
  # If true, this role was relevant in a previous version of the application but should no longer
  # be offered to the user in future sharing actions.  The role may still be displayed if it was
  # used to share the view while still running the old version.

  default @5 :Bool = false;
  # If true, this role should be used for any sharing actions that took place using a previous
  # version of the app that did not define any roles. This allows you to seamlessly add roles to
  # an already-deployed app without breaking existing shares. If you do not mark any roles as
  # "default", then such sharing actions will be treated as having an empty permissions set (the
  # user can open the grain, but the grain is told that the user has no permissions).
  #
  # See also `ViewSharingLink.RoleAssignment.none`, below.
}

interface SharingLink {
  # Represents one link in the sharing graph.

  getPetname @0 () -> (name :Util.Assignable(Util.LocalizedText));
  # Name assigned by the sharer to the recipient.
}

interface ViewSharingLink extends(SharingLink) {
  # A SharingLink for a UiView. These links can be attenuated with permissions.

  getRoleAssignment @0 () -> (var :Util.Assignable(RoleAssignment));
  # Returns an Assignable containing a RoleAssignment.

  struct RoleAssignment {
    union {
      none      @0: Void;
      # No role was explicitly chosen. The main case where this happens is when an app defining
      # no roles is shared. Note that "none" means "no role", but does NOT necessarily mean
      # "no permissions". If a default role is defined (see `RoleDef.default`), that will be used.

      allAccess @1 :Void;  # Grant all permissions.
      roleId @2 :UInt16;   # Grant permissions for the given role.
    }

    addPermissions @3 :Identity.PermissionSet;
    # Permissions to add on top of those granted above.

    removePermissions @4 :Identity.PermissionSet;
    # Permissions to remove from those granted above.
  }
}

# ========================================================================================
# Backup and Restore

struct GrainInfo {
  # Format of metadata file stored in grain backups.

  appId @0 :Text;
  appVersion @1 :UInt32;
  title @2 :Text;

  ownerIdentityId @3 :Text;

  users @4 :List(User);
  # Record of users with who had accessed this grain. This can be used to ensure that if a restored
  # grain is shared with the same users, they receive the same identities, rather than appearing
  # to be new people.

  struct User {
    identityId @0 :Text;
    # Identity ID of this user within the app.

    credentialIds @1 :List(Text);
    # The user's login credential IDs. If a user with a matching credential visits the restored
    # grain, they will regain the same identity. Credential IDs are consistent across differnt
    # Sandstorm servers (as long as the same authentication mechanisms are used), so this can allow
    # identities to be restored even on a new server.
    #
    # Non-login credentials are not included because those credentials could be shared by multiple
    # users. However, non-login credentials could be used for matching when restoring identities
    # later.

    profile @2 :Identity.Profile;
    # User's profile. Could be useful to allow the human owner of the restored grain to manually
    # remap identities.
  }

  originalGrainId @5 :Text;
  # The grain's original ID. With admin approval, grains could be allowed to receive the same IDs
  # when restored on a new server.

  # TODO(someday): Record the whole sharing / capability graph? This gets complicated since grains
  #   may have been shared via other grains, etc.
}

# ========================================================================================
# Persistent objects

interface AppPersistent @0xaffa789add8747b8 (AppObjectId) {
  # To make an object implemented by your own app persistent, implement this interface.
  #
  # `AppObjectId` is a structure like a URL which identifies a specific object within your app.
  # You may define this structure any way you want. For example, it could literally be a string
  # URL, or it could be a database ID, or it could actually be a serialized representation of an
  # object that isn't actually stored anywhere (like a "data URL").
  #
  # Other apps and external clients will never actually see your `AppObjectId`; it is stored by
  # Sandstorm itself, and clients only see an opaque token. Therefore, you need not encrypt, sign,
  # authenticate, or obfuscate this structure. Moreover, Sandstorm will ensure that only clients
  # who previously saved the object are able to restore it.
  #
  # Note: This interface is called `AppPersistent` rather than just `Persistent` to distinguish it
  #   from Cap'n Proto's `Persistent` interface, which is a more general (and more confusing)
  #   version of this concept. Many things that the general Cap'n Proto `Persistent` must deal
  #   with are handled by Sandstorm, so Sandstorm apps need not think about them. Cap'n Proto
  #   also uses the term `SturdyRef` rather than `ObjectId` -- the major difference is that
  #   `SturdyRef` is cryptographically secure whereas `ObjectId` need not be because it is
  #   protected by the platform.
  #
  # TODO(cleanup): Consider eliminating Cap'n Proto's `Persistent` interface in favor of having
  #   every realm define their own interface. Might actually be less confusing.

  save @0 () -> (objectId :AppObjectId, label :Util.LocalizedText);
  # Saves the capability to disk (if it isn't there already) and then returns the object ID which
  # can be passed to `MainView.restore()` to restore it later.
  #
  # The grain owner will be able to inspect externally-held capabilities via the UI. `label` will
  # be shown there and should briefly describe what this capability represents.
  #
  # Note that Sandstorm compares all object IDs your app produces for equality (using Cap'n Proto
  # canonicalization rules) so that it can recognize when the same object is saved multiple times.
  # `MainView.drop()` will be called when all such references have been dropped by their respective
  # clients.
  #
  # TODO(cleanup): How does `label` here relate to `PowerboxDisplayInfo` on `offer()` and
  #   `fulfillRequest()`? Maybe `label` here should actually be `PowerboxDisplayInfo` and those
  #   other methods shouldn't take that parameter?
}

interface MainView(AppObjectId) extends(UiView) {
  # The default (bootstrap) interface exported by a grain to the supervisor when it comes up is
  # actually `MainView`. Only the Supervisor sees this interface. It proxies the `UiView` subset
  # of the interface to the rest of the world, and automatically makes that capability persistent,
  # so that a simple app can completely avoid implementing persistence.
  #
  # `AppObjectId` is a structure type defined by the app which identifies persistent objects
  # within the app, like a URL. See `AppPersistent`, above.

  restore @0 (objectId :AppObjectId) -> (cap :Capability);
  # Restore a live object corresponding to an `AppObjectId`. See `AppPersistent`, above.
  #
  # Apps only need to implement this if they publish persistent capabilities (not including the
  # main UiView).

  drop @1 (objectId :AppObjectId);
  # Indicates that all external persistent references to the given persistent object have been
  # dropped. Depending on the nature of the underlying object, the app may wish to delete it at
  # this point.
  #
  # Note that this method is unreliable. Drop notifications rely on cooperation from the client,
  # who has to explicitly call `drop()` on their end when they discard the reference. Buggy clients
  # may forget to do this. Clients that are destroyed in a fire may have no opportunity to do this.
  # (This differs from live capabilities, which are tied to an ephemeral connection and implicitly
  # dropped when that connection is closed.)
  #
  # That said, Sandstorm gives the grain owner the ability to inspect incoming refs and revoke them
  # explicitly. If all refs to this object are revoked, then Sandstorm will call `drop()`.
  #
  # In some rare cases, `drop()` may be called more than once on the same object. The app should
  # make sure `drop()` is idempotent.
}
