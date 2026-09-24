import type { ButtonHTMLAttributes } from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '../../lib/utils';

const buttonVariants = cva('button', {
  variants: {
    variant: {
      default: 'button-dark',
      outline: 'button-outline',
      ghost: 'button-ghost',
    },
    size: { default: 'button-md', sm: 'button-sm' },
  },
  defaultVariants: { variant: 'default', size: 'default' },
});

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & VariantProps<typeof buttonVariants>;

export function Button({ className, variant, size, ...props }: ButtonProps) {
  return <button className={cn(buttonVariants({ variant, size, className }))} {...props} />;
}
