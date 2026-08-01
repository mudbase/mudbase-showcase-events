import { Controller, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { View } from "react-native";
import { z } from "zod";
import { useAuth } from "@/hooks/useAuth";
import { TextField } from "@/components/ui/TextField";
import { Button } from "@/components/ui/Button";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const loginSchema = z.object({
  email: z.string().min(1, "Email is required").email("Enter a valid email address"),
  password: z.string().min(1, "Password is required"),
});

type LoginFormValues = z.infer<typeof loginSchema>;

const DEMO_PASSWORD = "DemoTest123!";
const DEMO_ACCOUNTS = [
  { role: "Organizer", email: "events.organizer.demo@gmail.com" },
  { role: "Attendee", email: "events.attendee.demo@gmail.com" },
] as const;

export function LoginForm({ onSuccess }: { onSuccess: () => void }): React.JSX.Element {
  const { login, isSubmitting, error, clearError } = useAuth();
  const {
    control,
    handleSubmit,
    setValue,
    formState: { errors },
  } = useForm<LoginFormValues>({ resolver: zodResolver(loginSchema), defaultValues: { email: "", password: "" } });

  const onSubmit = async (values: LoginFormValues): Promise<void> => {
    clearError();
    const ok = await login(values.email, values.password);
    if (ok) onSuccess();
  };

  const quickFill = async (email: string): Promise<void> => {
    clearError();
    setValue("email", email);
    setValue("password", DEMO_PASSWORD);
    const ok = await login(email, DEMO_PASSWORD);
    if (ok) onSuccess();
  };

  return (
    <View className="gap-4">
      <View className="flex-row gap-2">
        {DEMO_ACCOUNTS.map((account) => (
          <Button
            key={account.role}
            variant="outline"
            size="sm"
            className="flex-1"
            disabled={isSubmitting}
            onPress={() => void quickFill(account.email)}
          >
            {account.role}
          </Button>
        ))}
      </View>

      {error && <ErrorNotice message={error} />}

      <Controller
        control={control}
        name="email"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Email"
            value={value}
            onChangeText={onChange}
            onBlur={onBlur}
            keyboardType="email-address"
            autoCapitalize="none"
            autoComplete="email"
            placeholder="events.organizer.demo@gmail.com"
            error={errors.email?.message}
          />
        )}
      />
      <Controller
        control={control}
        name="password"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Password"
            value={value}
            onChangeText={onChange}
            onBlur={onBlur}
            secureTextEntry
            autoComplete="current-password"
            error={errors.password?.message}
          />
        )}
      />
      <Button onPress={handleSubmit(onSubmit)} isLoading={isSubmitting}>
        {isSubmitting ? "Signing in…" : "Sign in"}
      </Button>
    </View>
  );
}
