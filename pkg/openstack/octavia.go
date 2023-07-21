/*
Copyright 2023.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package openstack

import (
	"context"
	"fmt"

	"github.com/openstack-k8s-operators/lib-common/modules/common/condition"
	"github.com/openstack-k8s-operators/lib-common/modules/common/helper"

	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	octaviav1 "github.com/openstack-k8s-operators/octavia-operator/api/v1beta1"
	corev1beta1 "github.com/openstack-k8s-operators/openstack-operator/apis/core/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
)

// ReconcileOctavia -
func ReconcileOctavia(ctx context.Context, instance *corev1beta1.OpenStackControlPlane, helper *helper.Helper) (ctrl.Result, error) {
	octavia := &octaviav1.Octavia{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "octavia",
			Namespace: instance.Namespace,
		},
	}

	if !instance.Spec.Octavia.Enabled {
		if res, err := EnsureDeleted(ctx, helper, octavia); err != nil {
			return res, err
		}
		instance.Status.Conditions.Remove(corev1beta1.OpenStackControlPlaneOctaviaReadyCondition)
		return ctrl.Result{}, nil
	}

	helper.GetLogger().Info("Reconciling Octavia", "Octavia.Namespace", instance.Namespace, "Octavia.Name", octavia.Name)
	op, err := controllerutil.CreateOrPatch(ctx, helper.GetClient(), octavia, func() error {
		instance.Spec.Octavia.Template.DeepCopyInto(&octavia.Spec)
		err := controllerutil.SetControllerReference(helper.GetBeforeObject(), octavia, helper.GetScheme())
		if err != nil {
			return err
		}
		return nil
	})

	if err != nil {
		instance.Status.Conditions.Set(condition.FalseCondition(
			corev1beta1.OpenStackControlPlaneOctaviaReadyCondition,
			condition.ErrorReason,
			condition.SeverityWarning,
			corev1beta1.OpenStackControlPlaneOctaviaReadyErrorMessage,
			err.Error()))
		return ctrl.Result{}, err
	}
	if op != controllerutil.OperationResultNone {
		helper.GetLogger().Info(fmt.Sprintf("Octavia %s - %s", octavia.Name, op))
	}

	if octavia.IsReady() {
		instance.Status.Conditions.MarkTrue(corev1beta1.OpenStackControlPlaneOctaviaReadyCondition, corev1beta1.OpenStackControlPlaneOctaviaReadyMessage)
	} else {
		instance.Status.Conditions.Set(condition.FalseCondition(
			corev1beta1.OpenStackControlPlaneOctaviaReadyCondition,
			condition.RequestedReason,
			condition.SeverityInfo,
			corev1beta1.OpenStackControlPlaneOctaviaReadyRunningMessage))
	}

	return ctrl.Result{}, nil
}
