package openstack

import (
	"context"
	"fmt"

	keystonev1 "github.com/openstack-k8s-operators/keystone-operator/api/v1beta1"
	"github.com/openstack-k8s-operators/lib-common/modules/common/helper"
	corev1beta1 "github.com/openstack-k8s-operators/openstack-operator/apis/core/v1beta1"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
)

// ReconcileApplicationCredentials ensures that every OpenStack service that
// has AC enabled service.applicationCredential.enabled: true gets a
// keystone.openstack.org/v1beta1 ApplicationCredential CR
func ReconcileApplicationCredentials(
	ctx context.Context,
	instance *corev1beta1.OpenStackControlPlane,
	_ *corev1beta1.OpenStackVersion, // currently unused
	helper *helper.Helper,
) (ctrl.Result, error) {

	log := GetLogger(ctx)

	if !instance.Spec.ApplicationCredential.Enabled {
		log.Info("Global .spec.applicationCredential.enabled is false – ensuring all AC CRs are deleted")

		// Try to delete any AC that might still exist for services in this namespace
		for _, name := range []string{
			"glance", "nova", "swift", "telemetry", "barbican",
			"cinder", "placement", "neutron",
		} {
			ac := &keystonev1.ApplicationCredential{
				ObjectMeta: metav1.ObjectMeta{
					Name:      fmt.Sprintf("ac-%s", name),
					Namespace: instance.Namespace,
				},
			}
			if res, err := EnsureDeleted(ctx, helper, ac); err != nil {
				return res, err
			}
		}
		return ctrl.Result{}, nil
	}

	type svcAC struct {
		Name      string
		Enabled   bool
		ACSection corev1beta1.ApplicationCredentialSection
	}
	svcs := []svcAC{
		{
			"glance",
			instance.Spec.Glance.Enabled,
			instance.Spec.Glance.ApplicationCredential,
		},
		{
			"nova",
			instance.Spec.Nova.Enabled,
			instance.Spec.Nova.ApplicationCredential,
		},
		{
			"swift",
			instance.Spec.Swift.Enabled,
			instance.Spec.Swift.ApplicationCredential,
		},
		{
			"ceilometer",
			instance.Spec.Telemetry.Enabled,
			instance.Spec.Telemetry.ApplicationCredential,
		},
		{
			"barbican",
			instance.Spec.Barbican.Enabled,
			instance.Spec.Barbican.ApplicationCredential,
		},
		{
			"cinder",
			instance.Spec.Cinder.Enabled,
			instance.Spec.Cinder.ApplicationCredential,
		},
		{
			"placement",
			instance.Spec.Placement.Enabled,
			instance.Spec.Placement.ApplicationCredential,
		},
		{
			"neutron",
			instance.Spec.Neutron.Enabled,
			instance.Spec.Neutron.ApplicationCredential,
		},
	}

	for _, svc := range svcs {

		acName := fmt.Sprintf("ac-%s", svc.Name)
		acObj := &keystonev1.ApplicationCredential{
			ObjectMeta: metav1.ObjectMeta{
				Name:      acName,
				Namespace: instance.Namespace,
			},
		}

		// Determine whether this AC should exist
		if !(svc.Enabled && svc.ACSection.Enabled) {
			// Service disabled or its AC disabled – ensure deletion
			if res, err := EnsureDeleted(ctx, helper, acObj); err != nil {
				return res, err
			}
			continue
		}

		// CreateOrPatch the AC CR
		op, err := controllerutil.CreateOrPatch(ctx, helper.GetClient(), acObj, func() error {

			acObj.Spec.UserName = svc.Name
			acObj.Spec.ExpirationDays = svc.ACSection.ExpirationDays
			acObj.Spec.GracePeriodDays = svc.ACSection.GracePeriodDays

			// Set owner reference to the control‑plane CR
			return controllerutil.SetControllerReference(
				helper.GetBeforeObject(), acObj, helper.GetScheme())
		})
		if err != nil {
			// Surface errors similarly to other service reconcilers
			return ctrl.Result{}, err
		}
		if op != controllerutil.OperationResultNone {
			log.Info("ApplicationCredential reconciled",
				"service", svc.Name, "operation", op)
		}
	}

	return ctrl.Result{}, nil
}
