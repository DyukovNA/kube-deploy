import { Button as BaseButton } from "@base-ui/react/button";
import type { ComponentProps } from "react";

type Props = ComponentProps<typeof BaseButton> & {
  tone?: "primary" | "quiet";
};

// Locally owned Base UI primitive, styled for the KubeDeploy visual system.
export function Button({ className = "", tone = "primary", ...props }: Props) {
  return <BaseButton className={`action-button action-button--${tone} ${className}`} {...props} />;
}
